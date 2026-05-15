/**
 * Model Wrapper — extends CubismUserModel with full SDK pipeline:
 * loading, motions, physics, expressions, eye blink, breath, look, draw.
 */

#ifndef CubismModel_h
#define CubismModel_h

#import <CubismFramework.hpp>
#import <Model/CubismUserModel.hpp>
#import <ICubismModelSetting.hpp>
#import <Type/csmRectF.hpp>
#import <Rendering/Metal/CubismRenderTarget_Metal.hpp>
#import <Motion/CubismMotionQueueEntry.hpp>

@class TextureLoader;

class CubismModelWrapper : public Csm::CubismUserModel
{
public:
    CubismModelWrapper();
    virtual ~CubismModelWrapper();

    void LoadAssets(const Csm::csmChar* dir, const Csm::csmChar* fileName,
                    float viewWidth, float viewHeight,
                    TextureLoader* textureLoader);

    void ReloadRenderer(float viewWidth, float viewHeight, TextureLoader* textureLoader);

    void Update(float speedMultiplier = 1.0f);

    Csm::ICubismModelSetting* GetModelSetting() { return _modelSetting; }

    void Draw(Csm::CubismMatrix44& matrix);

    Csm::CubismMotionQueueEntryHandle StartMotion(const Csm::csmChar* group, Csm::csmInt32 no, Csm::csmInt32 priority,
        Csm::ACubismMotion::FinishedMotionCallback onFinishedMotionHandler = NULL,
        Csm::ACubismMotion::BeganMotionCallback onBeganMotionHandler = NULL);

    Csm::CubismMotionQueueEntryHandle StartRandomMotion(const Csm::csmChar* group, Csm::csmInt32 priority,
        Csm::ACubismMotion::FinishedMotionCallback onFinishedMotionHandler = NULL,
        Csm::ACubismMotion::BeganMotionCallback onBeganMotionHandler = NULL);

    void SetExpression(const Csm::csmChar* expressionID);
    void SetRandomExpression();

    virtual Csm::csmBool HitTest(const Csm::csmChar* hitAreaName, Csm::csmFloat32 x, Csm::csmFloat32 y);

    Live2D::Cubism::Framework::Rendering::CubismRenderTarget_Metal& GetRenderBuffer();

    Csm::csmBool HasMocConsistencyFromFile(const Csm::csmChar* mocFileName);

    virtual void MotionEventFired(const Live2D::Cubism::Framework::csmString& eventValue);

    void SetDragPosition(Csm::csmFloat32 x, Csm::csmFloat32 y);
    void SetPhysicsEnabled(Csm::csmBool enabled);

    Csm::csmFloat32 GetCurrentMotionTime();
    Csm::csmFloat32 GetCurrentMotionDuration();
    void SeekMotionTo(Csm::csmFloat32 time);

protected:
    void DoDraw();

private:
    Csm::CubismMotionQueueEntry* GetLatestMotionEntry();
    void SetupModel(Csm::ICubismModelSetting* setting);
    void SetupTextures(TextureLoader* textureLoader);
    void PreloadMotionGroup(const Csm::csmChar* group);
    void ReleaseMotionGroup(const Csm::csmChar* group) const;
    void ReleaseMotions();
    void ReleaseExpressions();

    Csm::ICubismModelSetting* _modelSetting;
    Csm::csmString _modelHomeDir;
    Csm::csmFloat32 _userTimeSeconds;
    Csm::csmFloat32 _motionQueueTimeSeconds;
    Csm::csmVector<Csm::CubismIdHandle> _eyeBlinkIds;
    Csm::csmVector<Csm::CubismIdHandle> _lipSyncIds;
    Csm::csmMap<Csm::csmString, Csm::ACubismMotion*> _motions;
    Csm::csmMap<Csm::csmString, Csm::ACubismMotion*> _expressions;
    Csm::csmVector<Csm::csmRectF> _hitArea;
    Csm::csmVector<Csm::csmRectF> _userArea;
    const Csm::CubismId* _idParamAngleX;
    const Csm::CubismId* _idParamAngleY;
    const Csm::CubismId* _idParamAngleZ;
    const Csm::CubismId* _idParamBodyAngleX;
    const Csm::CubismId* _idParamEyeBallX;
    const Csm::CubismId* _idParamEyeBallY;
    Csm::csmBool _motionUpdated;
    Csm::csmBool _physicsEnabled;

    TextureLoader* _textureLoader;

    Live2D::Cubism::Framework::Rendering::CubismRenderTarget_Metal _renderBuffer;
};

#endif /* CubismModel_h */
