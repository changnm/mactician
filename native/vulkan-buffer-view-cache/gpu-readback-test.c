#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl32.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
static GLuint shader(GLenum type, const char *source) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &source, NULL);
    glCompileShader(s);
    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[4096];
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        puts(log);
        exit(1);
    }
    return s;
}
int main(void) {
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLint major, minor;
    if (!eglInitialize(display, &major, &minor)) {
        printf("eglInitialize %x\n", eglGetError());
        return 1;
    }
    EGLint config_attrs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE,
                             EGL_OPENGL_ES3_BIT, EGL_NONE};
    EGLConfig config;
    EGLint count;
    if (!eglChooseConfig(display, config_attrs, &config, 1, &count) || !count)
        return 1;
    EGLint context_attrs[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 2, EGL_NONE};
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attrs);
    if (context == EGL_NO_CONTEXT) {
        printf("eglCreateContext %x\n", eglGetError());
        return 1;
    }
    EGLint surface_attrs[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
    EGLSurface surface = eglCreatePbufferSurface(display, config, surface_attrs);
    if (!eglMakeCurrent(display, surface, surface, context))
        return 1;
    printf("renderer=%s version=%s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    const char *source = "#version 320 es\nprecision highp float; precision highp usamplerBuffer; "
                         "layout(local_size_x=1) in; layout(binding=0) uniform usamplerBuffer src; "
                         "layout(std430,binding=1) buffer Result {uint values[];}; uniform highp "
                         "uint outputIndex; void main(){values[outputIndex]=texelFetch(src,1).x;}";
    GLuint s = shader(GL_COMPUTE_SHADER, source), program = glCreateProgram();
    glAttachShader(program, s);
    glLinkProgram(program);
    GLint ok;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok)
        return 1;
    glUseProgram(program);
    GLint alignment;
    glGetIntegerv(GL_TEXTURE_BUFFER_OFFSET_ALIGNMENT, &alignment);
    if (alignment <= 0 || alignment > 1048576)
        return 1;
    GLint indexLocation = glGetUniformLocation(program, "outputIndex");
    const unsigned iterations = 128, texturesCount = 8, inputBytes = (unsigned)alignment * 3 + 128,
                   outputCount = iterations * texturesCount;
    uint32_t *upload = malloc(inputBytes), *expected = malloc(outputCount * 4);
    if (!upload || !expected)
        return 1;
    GLuint buffers[2], textures[8];
    glGenBuffers(2, buffers);
    glGenTextures(8, textures);
    glActiveTexture(GL_TEXTURE0);
    glBindBuffer(GL_TEXTURE_BUFFER, buffers[0]);
    glBufferData(GL_TEXTURE_BUFFER, inputBytes, NULL, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffers[1]);
    glBufferData(GL_SHADER_STORAGE_BUFFER, outputCount * 4, NULL, GL_DYNAMIC_DRAW);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, buffers[1]);
    for (unsigned iter = 0; iter < iterations; iter++) {
        for (unsigned word = 0; word < inputBytes / 4; word++)
            upload[word] = 0x01000000 + iter * 0x10000 + word;
        glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT);
        glBindBuffer(GL_TEXTURE_BUFFER, buffers[0]);
        if (iter % 16 == 0)
            glBufferData(GL_TEXTURE_BUFFER, inputBytes, upload, GL_DYNAMIC_DRAW);
        else
            glBufferSubData(GL_TEXTURE_BUFFER, 0, inputBytes, upload);
        for (unsigned slot = 0; slot < texturesCount; slot++) {
            unsigned group = slot % 4, offset = (group % 3) * (unsigned)alignment,
                     range = group < 2 ? 64 : 128;
            GLenum format = (group & 1) ? GL_RGBA32UI : GL_R32UI;
            glBindTexture(GL_TEXTURE_BUFFER, textures[slot]);
            glTexBufferRange(GL_TEXTURE_BUFFER, format, buffers[0], offset, range);
            unsigned output = iter * texturesCount + slot;
            expected[output] = upload[offset / 4 + ((group & 1) ? 4 : 1)];
            glUniform1ui(indexLocation, output);
            glDispatchCompute(1, 1, 1);
            if (glGetError() != GL_NO_ERROR) {
                printf("GL error at iteration %u slot %u\n", iter, slot);
                return 1;
            }
        }
        if (iter == 63) {
            glDeleteTextures(8, textures);
            glGenTextures(8, textures);
        }
        if (iter % 4 == 0) {
            struct timespec pause = {.tv_nsec = 100000000};
            nanosleep(&pause, NULL);
        }
    }
    glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);
    glFinish();
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffers[1]);
    uint32_t *mapped =
        glMapBufferRange(GL_SHADER_STORAGE_BUFFER, 0, outputCount * 4, GL_MAP_READ_BIT);
    if (!mapped || glGetError() != GL_NO_ERROR)
        return 1;
    for (unsigned i = 0; i < outputCount; i++)
        if (mapped[i] != expected[i]) {
            printf("readback FAIL index=%u actual=%x expected=%x\n", i, mapped[i], expected[i]);
            return 1;
        }
    glUnmapBuffer(GL_SHADER_STORAGE_BUFFER);
    printf("Async texture-buffer readbacks: %u PASS; 8 textures, duplicate active views, 2 "
           "formats, offsets/ranges, orphaning and recreation\n",
           outputCount);
    glDeleteTextures(8, textures);
    glDeleteBuffers(2, buffers);
    glDeleteProgram(program);
    glDeleteShader(s);
    free(upload);
    free(expected);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    return 0;
}
