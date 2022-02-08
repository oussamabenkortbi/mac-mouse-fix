//
// --------------------------------------------------------------------------
// GestureScrollSimulator.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2020
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import "GestureScrollSimulator.h"
#import <QuartzCore/QuartzCore.h>
#import <Cocoa/Cocoa.h>
#import "TouchSimulator.h"
#import "HelperUtility.h"
#import "SharedUtility.h"
#import "VectorSubPixelator.h"
#import "TransformationUtility.h"
#import "Mac_Mouse_Fix_Helper-Swift.h"
#import "WannabePrefixHeader.h"

/**
 This generates fliud scroll events containing gesture data similar to the Apple Trackpad or Apple Magic Mouse driver.
 The events that this generates don't exactly match the ones generated by the Apple Drivers. Most notably they don't contain any raw touch  information. But in most situations, they will work exactly like scrolling on an Apple Trackpad or Magic Mouse

Also see:
 - GestureScrollSimulatorOld.m - an older implementation which tried to emulate the Apple drivers more closely. See the notes in GestureScrollSimulatorOld.m for more info.
 - TouchExtractor-twoFingerSwipe.xcproj for the code we used to figure this out and more relevant notes.
 - Notes in other places I can't think of
 */


@implementation GestureScrollSimulator

#pragma mark - Constants

static double _pixelsPerLine = 10;
static double _preMomentumScrollMaxInterval = 0.1;
/// ^ Only start momentum scroll, if less than this time interval has passed between the kIOHIDEventPhaseEnded event and the last event before it (with a non-zero delta)
/// - 0.05 is a little too low. It will sometimes stop when you don't want it to when driving it through click and drag.
/// - 0.07 is still a little low when the computer is laggy

#pragma mark - Vars and init

static id<Smoother> _timeBetweenInputsSmoother; /// These smoothers might fit better into ModifiedDrag.m. They're specificly built for mouse-drag input.
static id<Smoother> _xDistanceSmoother;
static id<Smoother> _yDistanceSmoother;

static Vector _lastScrollPointVector; /// This is unused. Replaced by the smoothers above

//static VectorSubPixelator *_gesturePixelator;
//static VectorSubPixelator *_scrollPointPixelator;
static VectorSubPixelator *_scrollLinePixelator;

static PixelatedAnimator *_momentumAnimator;
//static BOOL _momentumScrollIsActive;
/// ^ We use this to avoid race conditions. It would be safer and easier (although maybe larginally slow?) to use a dispatch queue instead
///     Edit: Using dispatch queue now. This is not necessary anymore

static dispatch_queue_t _queue; /// Use this queue for interface functions to avoid race conditions

+ (void)initialize
{
    if (self == [GestureScrollSimulator class]) {
        
        /// Init dispatch queue
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, -1);
        _queue = dispatch_queue_create("com.nuebling.mac-mouse-fix.gesture-scroll", attr);
        
        /// Init smoothers
        
        int capacity = 5;
        
        _xDistanceSmoother = [[RollingAverage alloc] initWithCapacity:capacity];
        _yDistanceSmoother = [[RollingAverage alloc] initWithCapacity:capacity];
        _timeBetweenInputsSmoother = [[RollingAverage alloc] initWithCapacity:capacity];
        
//        double smoothingA = 0.2; /// 1.0 -> smoothing is off
//        double smoothingY = 0.8;
//        _xSpeedSmoother = [[DoubleExponentialSmoother alloc] initWithA:smoothingA y:smoothingY];
//        _ySpeedSmoother = [[DoubleExponentialSmoother alloc] initWithA:smoothingA y:smoothingY];
        
        
        /// Init Pixelators
        
//        _gesturePixelator = [VectorSubPixelator roundPixelator];
//        _scrollPointPixelator = [VectorSubPixelator roundPixelator];
        _scrollLinePixelator = [VectorSubPixelator biasedPixelator]; /// I think biased is only beneficial on linePixelator. Too lazy to explain.
        
        /// Momentum scroll
        
        _momentumAnimator = [[PixelatedAnimator alloc] init];
//        _momentumScrollIsActive = NO;
        
    }
}

#pragma mark - Main interface

/**
 Post scroll events that behave as if they are coming from an Apple Trackpad or Magic Mouse.
 This function is a wrapper for `postGestureScrollEventWithGestureVector:scrollVector:scrollVectorPoint:phase:momentumPhase:`

 Scrolling will continue automatically but get slower over time after the function has been called with phase kIOHIDEventPhaseEnded. (Momentum scroll)
 
    - The initial speed of this "momentum phase" is based on the delta values of last time that this function is called with at least one non-zero delta and with phase kIOHIDEventPhaseBegan or kIOHIDEventPhaseChanged before it is called with phase kIOHIDEventPhaseEnded.
 
    - The reason behind this is that this is how real trackpad input seems to work. Some apps like Xcode will automatically keep scrolling if no events are sent after the event with phase kIOHIDEventPhaseEnded. And others, like Safari will not. This function wil automatically keep sending events after it has been called with kIOHIDEventPhaseEnded in order to make all apps react as consistently as possible.
 
 \note In order to minimize momentum scrolling,  send an event with a very small but non-zero scroll delta before calling the function with phase kIOHIDEventPhaseEnded, or call stopMomentumScroll()
 \note For more info on which delta values and which phases to use, see the documentation for `postGestureScrollEventWithGestureDeltaX:deltaY:phase:momentumPhase:scrollDeltaConversionFunction:scrollPointDeltaConversionFunction:`. In contrast to the aforementioned function, you shouldn't need to call this function with kIOHIDEventPhaseUndefined.
*/

+ (void)postGestureScrollEventWithDeltaX:(int64_t)dx deltaY:(int64_t)dy phase:(IOHIDEventPhaseBits)phase {
    /// Schedule event to be posted on _queue and return immeditaly
    ///     Use this over `postGestureScrollEvent_Synchronously_WithDeltaX` when in doubt
    
    dispatch_async(_queue, ^{
        postGestureScrollEvent_Internal(dx, dy, phase);
    });
}

+ (void)postGestureScrollEvent_Synchronously_WithDeltaX:(int64_t)dx deltaY:(int64_t)dy phase:(IOHIDEventPhaseBits)phase {
    /// Schedule event to be posted on _queue and wait until it has been posted (and until momentum scroll has been started if phase is `kIOHIDEventPhaseEnd`)
    
    dispatch_sync(_queue, ^{
        postGestureScrollEvent_Internal(dx, dy, phase);
    });
}

void postGestureScrollEvent_Internal(int64_t dx, int64_t dy, IOHIDEventPhaseBits phase) {
    /// This function doesn't dispatch to _queue. It should only be called if your're already on _queue. Otherwise there will be race conditions with the other functions that execute on _queue.
    
    /// Debug
    
    //    DDLogDebug(@"Request to post Gesture Scroll: (%f, %f), phase: %d", dx, dy, phase);
    
    /// Validate input
    
    if (phase != kIOHIDEventPhaseEnded && dx == 0.0 && dy == 0.0) {
        /// Maybe kIOHIDEventPhaseBegan events from the Trackpad driver can also contain zero-deltas? I don't think so by I'm not sure.
        /// Real trackpad driver seems to only produce zero deltas when phase is kIOHIDEventPhaseEnded.
        ///     - (And probably also if phase is kIOHIDEventPhaseCancelled or kIOHIDEventPhaseMayBegin, but we're not using those here - IIRC those are only produced when the user touches the trackpad but doesn't begin scrolling before lifting fingers off again)
        /// The main practical reason we're emulating this behavour of the trackpad driver because of this: There are certain apps (or views?) which create their own momentum scrolls and ignore the momentum scroll deltas contained in the momentum scroll events we send. E.g. Xcode or the Finder collection view. I think that these views ignore all zero-delta events when they calculate what the initial momentum scroll speed should be. (It's been months since I discovered that though, so maybe I'm rememvering wrong) We want to match these apps momentum scroll algortihm closely to provide a consisten experience. So we're not sending the zero-delta events either and ignoring them for the purposes of our momentum scroll calculation and everything else.
        
        DDLogWarn(@"Trying to post gesture scroll with zero deltas while phase is not kIOHIDEventPhaseEnded - ignoring");
        
        return;
    }
    
    
    /// Stop momentum scroll
    ///     Do it sync otherwise it will be stopped immediately after it's startet by this block
    stopMomentumScroll_Sync();
    
    /// Timestamps and static vars
    
    static CFTimeInterval lastInputTime;
    static double smoothedXDistance;
    static double smoothedYDistance;
    static double smoothedTimeBetweenInputs;
    static CGPoint origin;
    
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval timeSinceLastInput;
    if (phase == kIOHIDEventPhaseBegan) {
        timeSinceLastInput = DBL_MAX; /// This means we can't say anything useful about the time since last input
    } else {
        timeSinceLastInput = now - lastInputTime;
    }
    
    /// Location
    
    //    CGPoint location = getPointerLocation();
    /// ^ Instead of using this, call getPointerLocation() directly before it's used so the value is as up-to-date as possible. Not sure if that makes a difference.
    
    /// Main
    
    if (phase == kIOHIDEventPhaseBegan) {
        
        origin = getPointerLocation();
        
        /// Reset subpixelators
        
        //            [_scrollPointPixelator reset];
        //            [_gesturePixelator reset];
        [_scrollLinePixelator reset];
        
        /// Reset smoothers
        [_xDistanceSmoother reset];
        [_yDistanceSmoother reset];
        [_timeBetweenInputsSmoother reset];
        smoothedXDistance = 0;
        smoothedYDistance = 0;
        smoothedTimeBetweenInputs = 0;
        
    }
    if (phase == kIOHIDEventPhaseBegan || phase == kIOHIDEventPhaseChanged) {
        
        /// Get vectors
        
        Vector vecScrollPoint = (Vector){ .x = dx, .y = dy };
        Vector vecScrollLine = scrollLineVector_FromScrollPointVector(vecScrollPoint);
        Vector vecGesture = gestureVector_FromScrollPointVector(vecScrollPoint);
        
        /// Record last scroll point vec
        
        _lastScrollPointVector = vecScrollPoint;
        
        /// Update smoothed values
        
        if (phase == kIOHIDEventPhaseChanged) {
            smoothedXDistance = [_xDistanceSmoother smoothWithValue:vecScrollPoint.x];
            smoothedYDistance = [_yDistanceSmoother smoothWithValue:vecScrollPoint.y];
            smoothedTimeBetweenInputs = [_timeBetweenInputsSmoother smoothWithValue:timeSinceLastInput];
            
        }
        
        /// Subpixelate vectors
        
        //            vecScrollPoint = [_scrollPointPixelator intVectorWithDoubleVector:vecScrollPoint]; /// Out input deltas dx and dy are pixels. No need to subpixelate
        //            vecGesture = [_gesturePixelator intVectorWithDoubleVector:vecGesture]; /// This is the same as vecScrollPoint
        //            vecScrollLine = [_scrollLinePixelator intVectorWithDoubleVector:vecScrollLine];
        
        /// Post events
        
        [GestureScrollSimulator postGestureScrollEventWithGestureVector:vecGesture
                                                       scrollVectorLine:vecScrollLine
                                                      scrollVectorPoint:vecScrollPoint
                                                                  phase:phase
                                                          momentumPhase:kCGMomentumScrollPhaseNone
                                                               location:getPointerLocation()];
        
        /// Debug
        //        DDLogInfo(@"timeSinceLast: %f scrollVec: %f %f speed: %f", timeSinceLastInput, vecScrollPoint.x, vecScrollPoint.y, vecScrollPoint.y / timeSinceLastInput);
        /// ^ We're trying to analyze what makes a sequence of (modifiedDrag) scrolls produce an absurly fast momentum Scroll in Xcode (Xcode has it's own momentumScroll algorirthm that doesn't just follow our smoothed algorithm)
        ///     I can't see a simple pattern. I don't get it.
        ///     I do see thought that the timeSinceLast fluctuates wildly. This might be part of the issue.
        ///         Solution idea: Feed the deltas from modifiedDrag into a display-synced coalescing loop. This coalescing loop will then call GestureScrollSimulator at most [refreshRate] times a second.
        
    } else if (phase == kIOHIDEventPhaseEnded) {
        
        /// Start momentum scroll
        
        DDLogInfo(@"timeSinceLast: %f", timeSinceLastInput);
        
        /// Update smoothers once more
        
        smoothedTimeBetweenInputs = [_timeBetweenInputsSmoother smoothWithValue:timeSinceLastInput];
        smoothedXDistance = [_xDistanceSmoother smoothWithValue:smoothedXDistance];
        smoothedYDistance = [_yDistanceSmoother smoothWithValue:smoothedYDistance];
        /// ^ kIOHIDEventPhaseEnded events always have distance 0. We're  inserting the last smoothed value as input instead of inserting 0 or nothing to maybe keep it more synced with the smoothedTimeBetweenInputs. Not sure if this is beneficial.
        
        
        /// Get exitSpeed (aka initialSpeed for momentum Scroll)
        
        Vector exitVelocity = (Vector){
            .x = smoothedXDistance / smoothedTimeBetweenInputs,
            .y = smoothedYDistance / smoothedTimeBetweenInputs
        };
        
        /// Post one more event with a delta
        ///     The speed in this last event should be exactly our smoothied speed.
        ///     We only do this because programs like Xcode and Finder implement their own momentum scroll algorithm and they sometimes react in a volatile way. Having the momentum scroll start either too slow or too fast.
        ///         We're already smoothing the speed over the last few input to the the initial speed for our momentumScroll implementation and it works really well. But it seems Xcode and others just ignore our momentumScroll events.
        ///         My theory is Xcode and other base their initial momentumScroll speed only on the speed in the last event before the kIOHIDEventPhaseEnded event.
        ///         So that's why were sending one extra event here with the smoothied speed - so that Xcode and other apps hopefully start momentumScroll with our smoothedSpeed
        
        //        double lastXDelta = timeSinceLastInput * exitVelocity.x * 1;
        //        double lastYDelta = timeSinceLastInput * exitVelocity.y * 1;
        /// ^ This seems to help a little but not much
        
        //        double lastXDelta = smoothedXDistance;
        //        double lastYDelta = smoothedYDistance;
        /// ^ Also very volatile
        
        /// Get vectors for last delta event
        
        //        Vector vecScrollPoint = (Vector){ .x = lastXDelta, .y = lastYDelta };
        //        Vector vecScrollLine = scrollLineVector_FromScrollPointVector(vecScrollPoint);
        //        Vector vecGesture = gestureVector_FromScrollPointVector(vecScrollPoint);
        //
        //        /// Post last delta event
        //        [self postGestureScrollEventWithGestureVector:vecGesture
        //                                     scrollVectorLine:vecScrollLine
        //                                    scrollVectorPoint:vecScrollPoint
        //                                                phase:kIOHIDEventPhaseChanged
        //                                        momentumPhase:0
        //                                             location:getPointerLocation()];
        
        /// Post `ended` event
        [GestureScrollSimulator postGestureScrollEventWithGestureVector:(Vector){}
                                                       scrollVectorLine:(Vector){}
                                                      scrollVectorPoint:(Vector){}
                                                                  phase:kIOHIDEventPhaseEnded
                                                          momentumPhase:0
                                                               location:getPointerLocation()];
        
        /// Get momentum scroll params
        
        double stopSpeed = 1.0;
        
        /// 1. Similar to trackpad, but to fast fall off on low speeds vs medium speeds
        ///     Can't really deviate from the default curve thought because certain apps impement their own momentumScroll and we should stay consistent with those
        ///     Maybe we can use a Bezier for the initialMomentumSpeed and make it feel better that way.
        double dragCoeff = 30;
        double dragExp = 0.7;
        
        /**
         For `dragExp`, a value between 0.7 and 0.8 seems to be the sweet spot to get nice Apple Trackpad -like deceleration
         - `dragExp` = 0.8 works well with `dragCoeff` around 30 (in the old implementation it used to be 8, so we probably messed something up in the new implementation)
         - `dragExp` = 0.7 works well with `dragCoeff` around 70
         - `dragExp` = 0.9  with `dragCoeff` around 10 also feels nice but noticeably different from Trackpad
         -   ^ The above drag coefficients don't work anymore now that we've fixed another bug where scroll point deltas were 10x too small
         */
        
        CGPoint location = origin;
        
        /// Do start momentum scroll
        
        startMomentumScroll(timeSinceLastInput, exitVelocity, stopSpeed, dragCoeff, dragExp, location);
        
    } else {
        DDLogError(@"Trying to send GestureScroll with invalid IOHIDEventPhase: %d", phase);
        assert(false);
    }
    
    lastInputTime = now; /// Make sure you don't return early so this is always executed
}

#pragma mark - Momentum scroll

static void (^_momentumScrollCallback)(void);

+ (void)afterStartingMomentumScroll:(void (^ _Nullable)(void))callback {
    /// `callback` will be called after the last `kIOHIDEventPhaseEnd` event has been sent, leading momentum scroll to be started
    ///     If it's decided that momentumScroll shouldn't be started because the `kIOHIDEventPhaseEnd` event had a too low delta or some other reason, then `callback` will be called right away.
    ///     If momentum scroll *is* started, then `callback` will be called after the first momentumScroll event has been sent.
    ///
    ///     This is only used by `ModifiedDrag`.
    ///     It probably shouldn't be sued by other classes, because of its specific behaviour and because, other classes might override eachothers callbacks, which would lead to really bad issues in ModifiedDrag
    
    dispatch_async(_queue, ^{
        
        if (_momentumAnimator.isRunning && callback != NULL) {
            /// ^ `&& callback != NULL` is a hack to make ModifiedDragOutputTwoFingerSwipe work properly. I'm not sure what I'm doing.
            
            DDLogError(@"Trying to set momentumScroll start callback while it's running. This can lead to bad issues and you probably don't want to do it.");
            assert(false);
        }
        
        _momentumScrollCallback = callback;
    });
}

/// Stop momentum scroll

+ (void)stopMomentumScroll {
    
//    DDLogDebug(@"momentumScroll stop request. Caller: %@", [SharedUtility callerInfo]);
    
    dispatch_async(_queue, ^{
        stopMomentumScroll_Sync();
    });
}

void stopMomentumScroll_Sync(void) {
    /// Only use this when you know you're already running on _queue
    
    //    DDLogDebug(@"momentumScroll stop request. Caller: %@", [SharedUtility callerInfo]);
    
    if (!_momentumAnimator.isRunning) {
//        DDLogDebug(@"... But momentumScroll insn't running");
    }
    
    if (_momentumAnimator.isRunning) {
        
        /// Stop our animator
        [_momentumAnimator stop];
        
        /// Debug
        DDLogDebug(@"... Sending momentumScroll stop event");
        
        /// Get event for location
        CGEventRef event = CGEventCreate(NULL);
        
        /// Get location from event
        CGPoint location = CGEventGetLocation(event);
        
        /// Send kCGMomentumScrollPhaseEnd event.
        ///  This will stop scrolling in apps like Xcode which implement their own momentum scroll algorithm
        Vector zeroVector = (Vector){ .x = 0.0, .y = 0.0 };
        [GestureScrollSimulator postGestureScrollEventWithGestureVector:zeroVector
                                                       scrollVectorLine:zeroVector
                                                      scrollVectorPoint:zeroVector
                                                                  phase:kIOHIDEventPhaseUndefined
                                                          momentumPhase:kCGMomentumScrollPhaseEnd
                                                               location:location];
    }
}

/// Momentum scroll main

static void startMomentumScroll(double timeSinceLastInput, Vector exitVelocity, double stopSpeed, double dragCoefficient, double dragExponent, CGPoint origin) {
    
    ///Debug
    
    DDLogDebug(@"momentumScroll start request");
    
//    DDLogDebug(@"Exit velocity: %f, %f", exitVelocity.x, exitVelocity.y);
    
    /// Declare constants
    
    Vector zeroVector = (Vector){ .x = 0, .y = 0 };
    
    /// Stop immediately, if too much time has passed since last event (So if the mouse is stationary)
    if (_preMomentumScrollMaxInterval < timeSinceLastInput
        || timeSinceLastInput == DBL_MAX) { /// This should never be true at this point, because it's only set to DBL_MAX when phase == kIOHIDEventPhaseBegan
        DDLogDebug(@"Not sending momentum scroll - timeSinceLastInput: %f", timeSinceLastInput);
        _momentumScrollCallback();
        [GestureScrollSimulator stopMomentumScroll];
        return;
    }
    
    /// Start animator
    
//    [_momentumAnimator startWithDuration:duration valueInterval:distanceInterval animationCurve:animationCurve
//                       integerCallback:^(NSInteger pointDelta, double timeDelta, MFAnimationPhase animationPhase) {
    
    
    /// Declare static
    ///     For communication between startParams callback and displayLinkCallback
    
    static Vector direction = { .x = 0, .y = 0 };
    
    /// Start animator
    
    [_momentumAnimator startWithParams:^NSDictionary<NSString *,id> * _Nonnull(double valueLeft, BOOL isRunning, id<AnimationCurve> _Nullable curve) {
        
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        
        /// Reset subpixelators
        
        //    [_scrollPointPixelator reset];
        [_scrollLinePixelator reset];
        /// Don't need to reset _gesturePixelator, because we don't send gesture events during momentum scroll
        
        /// Get animator params
        
        /// Get initial velocity
        Vector initialVelocity = initalMomentumScrollVelocity_FromExitVelocity(exitVelocity);
        
        /// Get initial speed
        double initialSpeed = magnitudeOfVector(initialVelocity); /// Magnitude is always positive
        
        /// Stop momentumScroll immediately, if the initial Speed is too small
        if (initialSpeed <= stopSpeed) {
            DDLogDebug(@"Not starting momentum scroll - initialSpeed smaller stopSpeed: i: %f, s: %f", initialSpeed, stopSpeed);
            _momentumScrollCallback();
            [GestureScrollSimulator stopMomentumScroll];
            p[@"doStart"] = @(NO);
            return p;
        }
        
        /// Get direction
        
        direction = unitVector(initialVelocity);
        
        /// Get drag animation curve
        
        DragCurve *animationCurve = [[DragCurve alloc] initWithCoefficient:dragCoefficient
                                                                  exponent:dragExponent
                                                              initialSpeed:initialSpeed
                                                                 stopSpeed:stopSpeed];
        
        /// Get duration and distance for animation from DragCurve
        
        double duration = animationCurve.timeInterval.length;
        double distance = animationCurve.distanceInterval.length;
        
        /// Return
        
        p[@"value"] = @(distance);
        p[@"duration"] = @(duration);
        p[@"curve"] = animationCurve;
        
        return p;
        
    } integerCallback:^(NSInteger pointDelta, double timeDelta, MFAnimationPhase animationPhase) {
        
        /// Validate state
        
        assert(animationPhase != kMFAnimationPhaseRunningStart);
        /// ^ _momentumAnimator should always be stopped before it is started again
        
        /// Debug
//        DDLogDebug(@"Momentum scrolling - delta: %ld, animationPhase: %d", (long)pointDelta, animationPhase);
        
        /// Get delta vectors
        Vector directedPointDelta = scaledVector(direction, pointDelta);
        Vector directedLineDelta = scrollLineVector_FromScrollPointVector(directedPointDelta);
        
        /// Subpixelate
//        Vector directedPointDeltaInt = [_scrollPointPixelator intVectorWithDoubleVector:directedPointDelta];
        ///     ^ Subpixelating the point delta not necessary since we're using PixelatedAnimator
        Vector directedPointDeltaInt = directedPointDelta;
        Vector directedLineDeltaInt = [_scrollLinePixelator intVectorWithDoubleVector:directedLineDelta];
        
        /// Call momentumScrollStart callback
        
        if (animationPhase == kMFAnimationPhaseStart
            || animationPhase == kMFAnimationPhaseStartAndEnd) {
            
            if (_momentumScrollCallback != NULL) _momentumScrollCallback();
        }
        
        /// Get momentumPhase from animationPhase
        
        CGMomentumScrollPhase momentumPhase;
        
        if (animationPhase == kMFAnimationPhaseStart) {
            momentumPhase = kCGMomentumScrollPhaseBegin;
        } else if (animationPhase == kMFAnimationPhaseContinue) {
            momentumPhase = kCGMomentumScrollPhaseContinue;
        } else if (animationPhase == kMFAnimationPhaseEnd
                   || animationPhase == kMFAnimationPhaseStartAndEnd) {
            /// Not sure how to deal with kMFAnimationPhaseStartAndEnd. Maybe we should set momentumPhase to kCGMomentumScrollPhaseBegin instead?
            momentumPhase = kCGMomentumScrollPhaseEnd;
        } else { /// We don't expect momentumPhase == kMFAnimationPhaseRunningStart
            assert(false);
        }
        
        /// Get pointer location for posting event
        CGPoint postLocation = getPointerLocation();
        
        /// Actuallly do stuff
        if (momentumPhase == kCGMomentumScrollPhaseEnd) {
            /// This is the last frame of the animation
            
            /// Send final kCGMomentumScrollPhaseContinue event
            [GestureScrollSimulator postGestureScrollEventWithGestureVector:zeroVector
                                                           scrollVectorLine:directedLineDeltaInt
                                                          scrollVectorPoint:directedPointDeltaInt
                                                                      phase:kIOHIDEventPhaseUndefined
                                                              momentumPhase:kCGMomentumScrollPhaseContinue
                                                                   location:postLocation];
            /// Send kCGMomentumScrollPhaseEnd event
            [GestureScrollSimulator postGestureScrollEventWithGestureVector:zeroVector
                                                           scrollVectorLine:zeroVector
                                                          scrollVectorPoint:zeroVector
                                                                      phase:kIOHIDEventPhaseUndefined
                                                              momentumPhase:kCGMomentumScrollPhaseEnd
                                                                   location:postLocation];
            
        } else { /// Default case - animationPhase != kMFAnimationPhaseEnd
            
            /// Post event
            [GestureScrollSimulator postGestureScrollEventWithGestureVector:zeroVector
                                                           scrollVectorLine:directedLineDeltaInt
                                                          scrollVectorPoint:directedPointDeltaInt
                                                                      phase:kIOHIDEventPhaseUndefined
                                                              momentumPhase:momentumPhase
                                                                   location:postLocation];
        }
    }];
    
}

#pragma mark - Vector math functions

static Vector scrollLineVector_FromScrollPointVector(Vector vec) {
    
    return scaledVectorWithFunction(vec, ^double(double x) {
        return x / _pixelsPerLine; /// See CGEventSource.pixelsPerLine - it's 10 by default
    });
}

static Vector gestureVector_FromScrollPointVector(Vector vec) {
    
    return scaledVectorWithFunction(vec, ^double(double x) {
//        return 1.35 * x; /// This makes swipe to mark unread in Apple Mail feel really nice
//        return 1.0 * x; /// This feels better for swiping between pages in Safari
//        return 1.15 * x; /// I think this is a nice compromise
        return 1.0 * x; /// Even 1.15 feels to fast right now.
    });
}

static Vector initalMomentumScrollVelocity_FromExitVelocity(Vector exitVelocity) {
    
    return scaledVectorWithFunction(exitVelocity, ^double(double x) {
//        return pow(fabs(x), 1.08) * sign(x);
        return x * 1;
    });
}

#pragma mark - Actually Synthesize and post events


/// Post scroll events that behave as if they are coming from an Apple Trackpad or Magic Mouse.
/// This allows for swiping between pages in apps like Safari or Preview, and it also makes overscroll and inertial scrolling work.
/// Phases
///     1. kIOHIDEventPhaseMayBegin - First event. Deltas should be 0.
///     2. kIOHIDEventPhaseBegan - Second event. At least one of the two deltas should be non-0.
///     4. kIOHIDEventPhaseChanged - All events in between. At least one of the two deltas should be non-0.
///     5. kIOHIDEventPhaseEnded - Last event before momentum phase. Deltas should be 0.
///       - If you stop sending events at this point, scrolling will continue in certain apps like Xcode, but get slower with time until it stops. The initial speed and direction of this "automatic momentum phase" seems to be based on the last kIOHIDEventPhaseChanged event which contained at least one non-zero delta.
///       - To stop this from happening, either give the last kIOHIDEventPhaseChanged event very small deltas, or send an event with phase kIOHIDEventPhaseUndefined and momentumPhase kCGMomentumScrollPhaseEnd right after this one.
///     6. kIOHIDEventPhaseUndefined - Use this phase with non-0 momentumPhase values. (0 being kCGMomentumScrollPhaseNone)
///     7. What about kIOHIDEventPhaseCanceled? It seems to occur when you touch the trackpad (producing MayBegin events) and then lift your fingers off before scrolling. I guess the deltas are always gonna be 0 on that, too, but I'm not sure.

+ (void)postGestureScrollEventWithGestureVector:(Vector)vecGesture
                               scrollVectorLine:(Vector)vecScroll
                              scrollVectorPoint:(Vector)vecScrollPoint
                                          phase:(IOHIDEventPhaseBits)phase
                                  momentumPhase:(CGMomentumScrollPhase)momentumPhase
                                       location:(CGPoint)loc {

    /// Debug
    
    static double tsLast = 0;
    double ts = CACurrentMediaTime();
    double timeSinceLast = ts - tsLast;
    tsLast = ts;
    
    DDLogDebug(@"\nPosting: gesture: (%f, %f) \t\t scroll: (%f, %f) \t scrollPt: (%f, %f) \t phases: (%d, %d) \t timeSinceLast: %f \t loc: (%f, %f)\n", vecGesture.x, vecGesture.y, vecScroll.x, vecScroll.y, vecScrollPoint.x, vecScrollPoint.y, phase, momentumPhase, timeSinceLast*1000, loc.x, loc.y);
    
    assert((phase == kIOHIDEventPhaseUndefined || momentumPhase == kCGMomentumScrollPhaseNone)); /// At least one of the phases has to be 0
    
    ///
    ///  Get stuff we need for both the type 22 and the type 29 event
    ///
    
    CGPoint eventLocation = loc;
    
    ///
    /// Create type 22 event
    ///     (scroll event)
    ///
    
    CGEventRef e22 = CGEventCreate(NULL);
    
    /// Set static fields
    
    CGEventSetDoubleValueField(e22, 55, 22); /// 22 -> NSEventTypeScrollWheel // Setting field 55 is the same as using CGEventSetType(), I'm not sure if that has weird side-effects though, so I'd rather do it this way.
    CGEventSetDoubleValueField(e22, 88, 1); /// 88 -> kCGScrollWheelEventIsContinuous
    CGEventSetDoubleValueField(e22, 137, 1); /// Maybe this is NSEvent.directionInvertedFromDevice
    
    /// Set dynamic fields
    
    /// Scroll deltas
    /// We used to round here, but rounding is not necessary, because we make sure that the incoming vectors only contain integers
    ///      Even if we didn't, I'm not sure rounding would make a difference
    /// Fixed point deltas are set automatically by setting these deltas IIRC.
    
    CGEventSetDoubleValueField(e22, 11, vecScroll.y); /// 11 -> kCGScrollWheelEventDeltaAxis1
    CGEventSetDoubleValueField(e22, 96, vecScrollPoint.y); /// 96 -> kCGScrollWheelEventPointDeltaAxis1
    
    CGEventSetDoubleValueField(e22, 12, vecScroll.x); /// 12 -> kCGScrollWheelEventDeltaAxis2
    CGEventSetDoubleValueField(e22, 97, vecScrollPoint.x); /// 97 -> kCGScrollWheelEventPointDeltaAxis2
    
    /// Phase
    
    CGEventSetDoubleValueField(e22, 99, phase);
    CGEventSetDoubleValueField(e22, 123, momentumPhase);

    
    if (phase != kIOHIDEventPhaseUndefined) {
//    if (momentumPhase == kCGMomentumScrollPhaseNone) {
            ///  ^ Not sure why we used to check for this instead of phase != kIOHIDEventPhaseUndefined. Remove this if the change didn't break anything.
        
        ///
        /// Create type 29 subtype 6 event
        ///     (gesture event)
        ///
        
        CGEventRef e29 = CGEventCreate(NULL);
        
        /// Set static fields
        
        CGEventSetDoubleValueField(e29, 55, 29); /// 29 -> NSEventTypeGesture // Setting field 55 is the same as using CGEventSetType()
        CGEventSetDoubleValueField(e29, 110, 6); /// 110 -> subtype // 6 -> kIOHIDEventTypeScroll
        
        /// Set dynamic fields
        
        double dxGesture = (double)vecGesture.x;
        double dyGesture = (double)vecGesture.y;
        if (dxGesture == 0) {
            dxGesture = -0.0f; /// The original events only contain -0 but this probably doesn't make a difference.
        }
        if (dyGesture == 0) {
            dyGesture = -0.0f; /// The original events only contain -0 but this probably doesn't make a difference.
        }
        CGEventSetDoubleValueField(e29, 116, dxGesture);
        CGEventSetDoubleValueField(e29, 119, dyGesture);
        
        CGEventSetIntegerValueField(e29, 132, phase);
        
        /// Post t29s6 events
        CGEventSetLocation(e29, eventLocation);
        CGEventPost(kCGSessionEventTap, e29);

        CFRelease(e29);
    }
    
    /// Post t22s0 event
    ///     Posting after the t29s6 event because I thought that was close to real trackpad events. But in real trackpad events the order is always different it seems.
    ///     Wow, posting this after the t29s6 events removed the little stutter when swiping between pages, nice!
    
    CGEventSetLocation(e22, eventLocation);
    CGEventPost(kCGSessionEventTap, e22); /// Needs to be kCGHIDEventTap instead of kCGSessionEventTap to work with Swish, but that will make the events feed back into our scroll event tap. That's not tooo bad, because we ignore continuous events anyways, still bad because CPU use and stuff.
    CFRelease(e22);
    
}

@end
