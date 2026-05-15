/**
 * Platform Abstraction Layer for Cubism SDK.
 * File loading via filesystem path (not NSBundle), time management, logging.
 */

#ifndef Pal_h
#define Pal_h

#import <string>
#import <CubismFramework.hpp>

class Pal
{
public:
    static void SetResourceBasePath(const std::string& basePath);

    static Csm::csmByte* LoadFileAsBytes(const std::string filePath, Csm::csmSizeInt* outSize);
    static void ReleaseBytes(Csm::csmByte* byteData);

    static double GetDeltaTime() { return s_deltaTime; }
    static void UpdateTime();

    static void PrintLogLn(const Csm::csmChar* format, ...);
    static void PrintMessageLn(const Csm::csmChar* message);

private:
    static double s_currentFrame;
    static double s_lastFrame;
    static double s_deltaTime;
    static std::string s_resourceBasePath;
};

#endif /* Pal_h */
