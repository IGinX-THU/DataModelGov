#ifndef SHT_MATLAB_LOADLIBRARY_STDIO_H
#define SHT_MATLAB_LOADLIBRARY_STDIO_H

/*
 * MATLAB loadlibrary only needs the FILE pointer used by internal helper
 * prototypes. An opaque declaration avoids parsing the full Windows UCRT.
 * This header is parser-only and is never used to build the engine DLL.
 */
typedef struct SHT_MATLAB_OPAQUE_FILE FILE;

#endif
