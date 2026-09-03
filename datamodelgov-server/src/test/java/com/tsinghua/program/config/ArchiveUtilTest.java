package com.tsinghua.program.config;

import com.tsinghua.util.ArchiveUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ArchiveUtilTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void rejectsZipEntriesOutsideTargetDirectory() throws Exception {
        Path archive = temporaryDirectory.resolve("unsafe.zip");
        try (ZipOutputStream output = new ZipOutputStream(new FileOutputStream(archive.toFile()))) {
            output.putNextEntry(new ZipEntry("../outside.txt"));
            output.write(new byte[]{1});
            output.closeEntry();
        }
        File target = temporaryDirectory.resolve("target").toFile();
        Files.createDirectories(target.toPath());
        assertThrows(IOException.class, () -> ArchiveUtil.extractArchive(archive.toFile(), target));
        assertFalse(Files.exists(temporaryDirectory.resolve("outside.txt")));
    }
}
