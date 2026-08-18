package com.tsinghua.util;

import lombok.extern.slf4j.Slf4j;
import net.sf.sevenzipjbinding.ExtractOperationResult;
import net.sf.sevenzipjbinding.IInArchive;
import net.sf.sevenzipjbinding.SevenZip;
import net.sf.sevenzipjbinding.SevenZipException;
import net.sf.sevenzipjbinding.SevenZipNativeInitializationException;
import net.sf.sevenzipjbinding.impl.RandomAccessFileInStream;
import net.sf.sevenzipjbinding.simple.ISimpleInArchive;
import net.sf.sevenzipjbinding.simple.ISimpleInArchiveItem;
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry;
import org.apache.commons.compress.archivers.sevenz.SevenZFile;
import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.GZIPInputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * 压缩包解压工具：支持 zip/rar/7z/tar/tar.gz/tgz。
 * RAR 通过 SevenZipJBinding 解压，初始化失败时 {@link #isSevenZipAvailable()} 返回 false。
 */
@Slf4j
public final class ArchiveUtil {

    private ArchiveUtil() {
    }

    public static final Set<String> SUPPORTED_ARCHIVE =
            new HashSet<>(Arrays.asList(".zip", ".rar", ".7z", ".tar", ".tar.gz", ".tgz"));

    private static final boolean SEVENZIP_AVAILABLE;

    static {
        boolean available = false;
        try {
            SevenZip.initSevenZipFromPlatformJAR();
            available = true;
        } catch (SevenZipNativeInitializationException e) {
            log.error("SevenZipJBinding 初始化失败", e);
        }
        SEVENZIP_AVAILABLE = available;
    }

    /** SevenZipJBinding 是否初始化成功（RAR 解压依赖它） */
    public static boolean isSevenZipAvailable() {
        return SEVENZIP_AVAILABLE;
    }

    /** 判断文件名是否为支持的压缩格式 */
    public static boolean isSupportedArchive(String filename) {
        String ext = getExtension(filename);
        return ext != null && SUPPORTED_ARCHIVE.contains(ext);
    }

    /**
     * 根据扩展名自动选择解压器把 archive 解压到 targetDir。
     * 不支持的格式抛 {@link IOException}。
     */
    public static void extractArchive(File archive, File targetDir) throws IOException {
        String ext = getExtension(archive.getName());
        if (".zip".equals(ext) || ".jar".equals(ext)) {
            extractZip(archive, targetDir);
        } else if (".rar".equals(ext)) {
            extractRar(archive, targetDir);
        } else if (".7z".equals(ext)) {
            extractSevenZ(archive, targetDir);
        } else if (".tar".equals(ext)) {
            extractTar(archive, targetDir);
        } else if (".tar.gz".equals(ext) || ".tgz".equals(ext)) {
            extractTarGz(archive, targetDir);
        } else {
            throw new IOException("不支持的压缩格式: " + ext);
        }
    }

    /** 取文件扩展名（小写，含点）。复合扩展名 .tar.gz / .tar.bz2 / .tar.xz 优先匹配。 */
    public static String getExtension(String filename) {
        String lower = filename.toLowerCase();
        if (lower.endsWith(".tar.gz")) return ".tar.gz";
        if (lower.endsWith(".tar.bz2")) return ".tar.bz2";
        if (lower.endsWith(".tar.xz")) return ".tar.xz";
        int dot = lower.lastIndexOf('.');
        return dot < 0 ? null : lower.substring(dot);
    }

    /** 去掉压缩包扩展名，得到程序名（兼容 .tar.gz / .tar.bz2 / .tar.xz）。 */
    public static String removeArchiveExtension(String filename) {
        String lower = filename.toLowerCase();
        if (lower.endsWith(".tar.gz")) return filename.substring(0, filename.length() - 7);
        if (lower.endsWith(".tar.bz2")) return filename.substring(0, filename.length() - 8);
        if (lower.endsWith(".tar.xz")) return filename.substring(0, filename.length() - 7);
        int dot = filename.lastIndexOf('.');
        return dot < 0 ? filename : filename.substring(0, dot);
    }

    private static void extractZip(File src, File targetDir) throws IOException {
        try (ZipInputStream zis = new ZipInputStream(new FileInputStream(src))) {
            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(f)) {
                        byte[] buf = new byte[8192];
                        int len;
                        while ((len = zis.read(buf)) > 0) fos.write(buf, 0, len);
                    }
                }
                zis.closeEntry();
            }
        }
    }

    private static void extractRar(File src, File targetDir) throws IOException {
        if (!SEVENZIP_AVAILABLE) {
            throw new IOException("SevenZipJBinding 未初始化，无法解压 RAR 文件");
        }
        try (RandomAccessFile raf = new RandomAccessFile(src, "r")) {
            IInArchive inArchive = SevenZip.openInArchive(null, new RandomAccessFileInStream(raf));
            try {
                ISimpleInArchive simple = inArchive.getSimpleInterface();
                for (ISimpleInArchiveItem item : simple.getArchiveItems()) {
                    final File out = new File(targetDir, item.getPath());
                    if (item.isFolder()) {
                        out.mkdirs();
                    } else {
                        out.getParentFile().mkdirs();
                        try (FileOutputStream fos = new FileOutputStream(out)) {
                            ExtractOperationResult result = item.extractSlow(data -> {
                                try {
                                    fos.write(data);
                                } catch (IOException e) {
                                    throw new SevenZipException("写入文件失败: " + out.getName(), e);
                                }
                                return data.length;
                            });
                            if (result != ExtractOperationResult.OK) {
                                throw new IOException("解压条目失败 " + item.getPath() + ": " + result);
                            }
                        }
                    }
                }
            } finally {
                if (inArchive != null) {
                    try { inArchive.close(); } catch (IOException ignored) {}
                }
            }
        }
    }

    private static void extractSevenZ(File src, File targetDir) throws IOException {
        try (SevenZFile sevenZFile = new SevenZFile(src)) {
            SevenZArchiveEntry entry;
            while ((entry = sevenZFile.getNextEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (InputStream is = sevenZFile.getInputStream(entry);
                         FileOutputStream fos = new FileOutputStream(f)) {
                        copy(is, fos);
                    }
                }
            }
        }
    }

    private static void extractTar(File src, File targetDir) throws IOException {
        try (TarArchiveInputStream tis = new TarArchiveInputStream(new FileInputStream(src))) {
            TarArchiveEntry entry;
            while ((entry = tis.getNextTarEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(f)) {
                        copy(tis, fos);
                    }
                }
            }
        }
    }

    private static void extractTarGz(File src, File targetDir) throws IOException {
        try (TarArchiveInputStream tis = new TarArchiveInputStream(new GZIPInputStream(new FileInputStream(src)))) {
            TarArchiveEntry entry;
            while ((entry = tis.getNextTarEntry()) != null) {
                File f = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    f.mkdirs();
                } else {
                    f.getParentFile().mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(f)) {
                        copy(tis, fos);
                    }
                }
            }
        }
    }

    private static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[8192];
        int len;
        while ((len = in.read(buf)) >= 0) {
            out.write(buf, 0, len);
        }
    }
}
