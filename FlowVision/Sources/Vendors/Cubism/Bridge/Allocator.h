/**
 * Memory Allocator for CubismFramework::StartUp.
 * Standard malloc/free implementation.
 */

#ifndef Allocator_h
#define Allocator_h

#import "CubismFramework.hpp"
#import "ICubismAllocator.hpp"

class Allocator : public Csm::ICubismAllocator
{
    void* Allocate(const Csm::csmSizeType size);
    void Deallocate(void* memory);
    void* AllocateAligned(const Csm::csmSizeType size, const Csm::csmUint32 alignment);
    void DeallocateAligned(void* alignedMemory);
};

#endif /* Allocator_h */
