// Layout of the private MultitouchSupport.framework frame data.
// The framework itself is loaded at runtime via dlopen (see Multitouch.swift).
#pragma once
#include <stdint.h>

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;

// Touch states reported in MTTouch.state
enum {
    MTStateNotTracking = 0,
    MTStateStartInRange = 1,
    MTStateHoverInRange = 2,
    MTStateMakeTouch = 3,
    MTStateTouching = 4,
    MTStateBreakTouch = 5,
    MTStateLingerInRange = 6,
    MTStateOutOfRange = 7,
};

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;      // stable per finger while it touches
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalized;    // 0..1, origin bottom-left
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;      // millimetres
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int32_t (*MTFrameCallback)(MTDeviceRef device, const MTTouch *touches, int32_t count, double timestamp, int32_t frame);
