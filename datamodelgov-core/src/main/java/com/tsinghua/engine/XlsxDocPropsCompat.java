package com.tsinghua.engine;

import lombok.extern.slf4j.Slf4j;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.Enumeration;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

/**
 * 交付 Excel 的 OPC 元数据兼容补丁（只补部件，不动任何单元格）。
 *
 * <p>背景：MATLAB {@code writetable} 产出的 xlsx 不含 {@code docProps/app.xml}。交付程序里
 * {@code sht_f3_business_identity/local_workbook} 用 {@code xlsfinfo} 枚举工作表名，而
 * {@code xlsfinfo} 在 Windows 上优先走 Excel COM；COM 起不来（Excel 未安装/被占用/跨会话）
 * 时回退到 {@code xlsfinfoXLSX}，该回退第一步就是 {@code fileread(docProps/app.xml)}。
 * 部件缺失 → 回退抛异常 → {@code xlsfinfo} 的 description 不是“sheet 名 cell”，
 * 而是一段**错误文本**。调用处写的是 {@code if ~ismember(sheet{1},sheets),continue;end}：
 * MATLAB 对 char 与 char 调 ismember 是**逐字符**比较，错误文本里只要出现 sheet 名中的
 * 任意一个字符（路径里的 'a'、'o' 就够）守卫就失效，于是 {@code readtable(file,'Sheet','Manifest')}
 * 被真的执行，报「工作表名称 'Manifest' 不存在或不受支持」——即使该工作簿根本没有 Manifest 表。
 *
 * <p>修复：给传给 MATLAB 的 xlsx 生成一份**补齐 docProps 部件**的副本，内容零改动。补齐后
 * 非 COM 回退能正常枚举 sheet，守卫恢复语义，业务身份读取只读真实存在的表。
 */
@Slf4j
public final class XlsxDocPropsCompat {

    /** 固定 zip 条目时间，保证同一源文件多次补丁产物字节一致（父工作簿 SHA 稳定，
     *  confirm 与 run 的 identity 才不会误报「已确认选择或数据改变」）。 */
    private static final long FIXED_TIME = 315532800000L; // 1980-01-01T00:00:00Z

    private static final String APP_PART = "docProps/app.xml";
    private static final String CORE_PART = "docProps/core.xml";

    private static final String APP_XML =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                    + "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\""
                    + " xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">"
                    + "<Application>Microsoft Excel</Application><DocSecurity>0</DocSecurity>"
                    + "<ScaleCrop>false</ScaleCrop><LinksUpToDate>false</LinksUpToDate>"
                    + "<SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged>"
                    + "<AppVersion>16.0300</AppVersion></Properties>";

    private static final String CORE_XML =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                    + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\""
                    + " xmlns:dc=\"http://purl.org/dc/elements/1.1/\""
                    + " xmlns:dcterms=\"http://purl.org/dc/terms/\""
                    + " xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\""
                    + " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
                    + "<dc:creator>DataModelGov</dc:creator>"
                    + "<cp:lastModifiedBy>DataModelGov</cp:lastModifiedBy>"
                    + "</cp:coreProperties>";

    private XlsxDocPropsCompat() {
    }

    /**
     * 确保 {@code source} 有一份带 docProps 的等价副本，返回应交给 MATLAB 使用的文件。
     * 已经含 {@code docProps/app.xml} 的文件原样返回（不复制）。
     *
     * @param source 原始 xlsx
     * @param dir    副本目录（调用方保证位于任务工作目录下）
     * @return 可直接传给 MATLAB 的文件
     */
    public static File ensure(File source, File dir) {
        if (source == null || !source.isFile()) return source;
        String name = source.getName();
        if (!name.toLowerCase().endsWith(".xlsx") && !name.toLowerCase().endsWith(".xlsm")) return source;
        try {
            if (hasPart(source, APP_PART)) return source;
            File dst = new File(dir, name);
            if (isUsableCopy(source, dst)) return dst;
            if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建目录: " + dir);
            writePatched(source, dst);
            log.info("交付Excel补齐docProps部件(规避xlsfinfo非COM回退失败): {} -> {}", source.getAbsolutePath(), dst.getAbsolutePath());
            return dst;
        } catch (Exception e) {
            // 补丁失败不阻断业务：退回原文件，由 MATLAB 侧报原始错误
            log.warn("交付Excel docProps补丁失败,沿用原文件: {} ({})", source.getAbsolutePath(), e.toString());
            return source;
        }
    }

    private static boolean hasPart(File xlsx, String part) throws IOException {
        try (ZipFile z = new ZipFile(xlsx)) {
            return z.getEntry(part) != null;
        }
    }

    /** 副本可用且不旧于源文件（源文件被重写后必须重新生成，否则 MATLAB 读到旧内容）。 */
    private static boolean isUsableCopy(File source, File dst) {
        return dst.isFile() && dst.length() > 0 && dst.lastModified() >= source.lastModified();
    }

    private static void writePatched(File source, File dst) throws IOException {
        Set<String> seen = new LinkedHashSet<>();
        File tmp = new File(dst.getParentFile(), dst.getName() + ".tmp");
        try (ZipFile zin = new ZipFile(source);
             ZipOutputStream out = new ZipOutputStream(Files.newOutputStream(tmp.toPath()))) {
            Enumeration<? extends ZipEntry> en = zin.entries();
            while (en.hasMoreElements()) {
                ZipEntry e = en.nextElement();
                String n = e.getName();
                seen.add(n);
                byte[] data;
                if ("[Content_Types].xml".equals(n)) {
                    data = patchContentTypes(readAll(zin, e));
                } else if ("_rels/.rels".equals(n)) {
                    data = patchRootRels(readAll(zin, e));
                } else {
                    data = readAll(zin, e);
                }
                putEntry(out, n, data);
            }
            if (!seen.contains(APP_PART)) putEntry(out, APP_PART, APP_XML.getBytes(StandardCharsets.UTF_8));
            if (!seen.contains(CORE_PART)) putEntry(out, CORE_PART, CORE_XML.getBytes(StandardCharsets.UTF_8));
        }
        try {
            Files.move(tmp.toPath(), dst.toPath(), StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            Files.deleteIfExists(tmp.toPath());
            throw e;
        }
        dst.setLastModified(System.currentTimeMillis());
    }

    private static void putEntry(ZipOutputStream out, String name, byte[] data) throws IOException {
        ZipEntry e = new ZipEntry(name);
        e.setTime(FIXED_TIME);
        out.putNextEntry(e);
        out.write(data);
        out.closeEntry();
    }

    private static byte[] readAll(ZipFile z, ZipEntry e) throws IOException {
        try (InputStream in = z.getInputStream(e)) {
            ByteArrayOutputStream bo = new ByteArrayOutputStream(Math.max(1024, (int) Math.max(0, e.getSize())));
            copy(in, bo);
            return bo.toByteArray();
        }
    }

    private static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
    }

    private static byte[] patchContentTypes(byte[] xml) {
        String s = new String(xml, StandardCharsets.UTF_8);
        StringBuilder add = new StringBuilder();
        if (!s.contains("/docProps/app.xml")) {
            add.append("<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>");
        }
        if (!s.contains("/docProps/core.xml")) {
            add.append("<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>");
        }
        if (add.length() == 0) return xml;
        int idx = s.lastIndexOf("</Types>");
        if (idx < 0) return xml;
        String patched = s.substring(0, idx) + add + s.substring(idx);
        return patched.getBytes(StandardCharsets.UTF_8);
    }

    private static byte[] patchRootRels(byte[] xml) {
        String s = new String(xml, StandardCharsets.UTF_8);
        StringBuilder add = new StringBuilder();
        if (!s.contains("Target=\"docProps/app.xml\"") && !s.contains("Target=\"/docProps/app.xml\"")) {
            add.append("<Relationship Id=\"rIdDmgAppProps\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/>");
        }
        if (!s.contains("Target=\"docProps/core.xml\"") && !s.contains("Target=\"/docProps/core.xml\"")) {
            add.append("<Relationship Id=\"rIdDmgCoreProps\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>");
        }
        if (add.length() == 0) return xml;
        int idx = s.lastIndexOf("</Relationships>");
        if (idx < 0) return xml;
        String patched = s.substring(0, idx) + add + s.substring(idx);
        return patched.getBytes(StandardCharsets.UTF_8);
    }
}
