/**
 * Platform Abstraction Layer implementation.
 * Loads files from filesystem using s_resourceBasePath prefix.
 */

#import "Pal.h"
#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import <stdarg.h>

using namespace Csm;
using namespace std;

double Pal::s_currentFrame = 0.0;
double Pal::s_lastFrame = 0.0;
double Pal::s_deltaTime = 0.0;
std::string Pal::s_resourceBasePath = "";

void Pal::SetResourceBasePath(const std::string& basePath)
{
    s_resourceBasePath = basePath;
    if (!s_resourceBasePath.empty() && s_resourceBasePath.back() != '/')
    {
        s_resourceBasePath += '/';
    }
}

csmByte* Pal::LoadFileAsBytes(const string filePath, csmSizeInt* outSize)
{
    std::string fullPath;
    if (filePath.front() == '/')
    {
        fullPath = filePath;
    }
    else
    {
        fullPath = s_resourceBasePath + filePath;
    }

    NSString* nsPath = [NSString stringWithUTF8String:fullPath.c_str()];
    NSData* data = [NSData dataWithContentsOfFile:nsPath];

    if (data == nil)
    {
        PrintLogLn("[Pal] File load failed: %s", fullPath.c_str());
        return NULL;
    }
    else if (data.length == 0)
    {
        PrintLogLn("[Pal] File loaded but size is zero: %s", fullPath.c_str());
        return NULL;
    }

    NSUInteger len = [data length];
    Byte* byteData = (Byte*)malloc(len + 1);
    memcpy(byteData, [data bytes], len);
    byteData[len] = 0;

    *outSize = static_cast<csmSizeInt>(len);
    return static_cast<csmByte*>(byteData);
}

void Pal::ReleaseBytes(csmByte* byteData)
{
    free(byteData);
}

void Pal::UpdateTime()
{
    NSDate* now = [NSDate date];
    double unixtime = [now timeIntervalSince1970];
    s_currentFrame = unixtime;
    s_deltaTime = s_currentFrame - s_lastFrame;
    s_lastFrame = s_currentFrame;
}

void Pal::PrintLogLn(const csmChar* format, ...)
{
    va_list args;
    csmChar buf[256];
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    NSLog(@"%@", [NSString stringWithCString:buf encoding:NSUTF8StringEncoding]);
    va_end(args);
}

void Pal::PrintMessageLn(const csmChar* message)
{
    PrintLogLn("%s", message);
}
