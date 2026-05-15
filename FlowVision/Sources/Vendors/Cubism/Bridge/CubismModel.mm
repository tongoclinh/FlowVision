/**
 * Model Wrapper implementation — full SDK pipeline.
 * Renamed from PoCModel to CubismModelWrapper. Added SetDragPosition and SetPhysicsEnabled.
 */

#import "CubismModel.h"
#import <Foundation/Foundation.h>
#import <fstream>
#import <vector>
#import "Pal.h"
#import "TextureLoader.h"
#import <CubismDefaultParameterId.hpp>
#import <CubismModelSettingJson.hpp>
#import <Id/CubismIdManager.hpp>
#import <Motion/CubismMotion.hpp>
#import <Motion/CubismMotionQueueEntry.hpp>
#import <Physics/CubismPhysics.hpp>
#import <Rendering/Metal/CubismRenderer_Metal.hpp>
#import <Utils/CubismString.hpp>
#import "Motion/CubismBreathUpdater.hpp"
#import "Motion/CubismLookUpdater.hpp"
#import "Motion/CubismExpressionUpdater.hpp"
#import "Motion/CubismEyeBlinkUpdater.hpp"
#import "Motion/CubismPhysicsUpdater.hpp"
#import "Motion/CubismPoseUpdater.hpp"

using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Framework::DefaultParameterId;

static const Csm::csmInt32 PriorityNone = 0;
static const Csm::csmInt32 PriorityIdle = 1;
static const Csm::csmInt32 PriorityNormal = 2;
static const Csm::csmInt32 PriorityForce = 3;

static const Csm::csmChar* MotionGroupIdle = "Idle";

namespace {
    Csm::csmByte* CreateBuffer(const Csm::csmChar* path, Csm::csmSizeInt* size)
    {
        return Pal::LoadFileAsBytes(path, size);
    }

    void DeleteBuffer(Csm::csmByte* buffer, const Csm::csmChar* path = "")
    {
        Pal::ReleaseBytes(buffer);
    }
}

CubismModelWrapper::CubismModelWrapper()
    : CubismUserModel()
    , _modelSetting(NULL)
    , _userTimeSeconds(0.0f)
    , _motionQueueTimeSeconds(0.0)
    , _pendingSeekTime(0.0f)
    , _hasPendingSeek(false)
    , _motionUpdated(false)
    , _physicsEnabled(true)
    , _loopingEnabled(false)
    , _lastMotionNo(-1)
    , _textureLoader(NULL)
{
    _mocConsistency = true;
    _debugMode = false;

    _idParamAngleX = CubismFramework::GetIdManager()->GetId(ParamAngleX);
    _idParamAngleY = CubismFramework::GetIdManager()->GetId(ParamAngleY);
    _idParamAngleZ = CubismFramework::GetIdManager()->GetId(ParamAngleZ);
    _idParamBodyAngleX = CubismFramework::GetIdManager()->GetId(ParamBodyAngleX);
    _idParamEyeBallX = CubismFramework::GetIdManager()->GetId(ParamEyeBallX);
    _idParamEyeBallY = CubismFramework::GetIdManager()->GetId(ParamEyeBallY);
}

CubismModelWrapper::~CubismModelWrapper()
{
    _renderBuffer.DestroyRenderTarget();

    ReleaseMotions();
    ReleaseExpressions();

    if (_modelSetting)
    {
        for (Csm::csmInt32 i = 0; i < _modelSetting->GetMotionGroupCount(); i++)
        {
            const Csm::csmChar* group = _modelSetting->GetMotionGroupName(i);
            ReleaseMotionGroup(group);
        }

        if (_textureLoader)
        {
            for (Csm::csmInt32 modelTextureNumber = 0; modelTextureNumber < _modelSetting->GetTextureCount(); modelTextureNumber++)
            {
                if (!strcmp(_modelSetting->GetTextureFileName(modelTextureNumber), ""))
                {
                    continue;
                }
                Csm::csmString texturePath = _modelSetting->GetTextureFileName(modelTextureNumber);
                texturePath = _modelHomeDir + texturePath;
                [_textureLoader releaseTextureByName:texturePath.GetRawString()];
            }
        }

        delete _modelSetting;
    }
}

void CubismModelWrapper::LoadAssets(const Csm::csmChar* dir, const Csm::csmChar* fileName,
                             float viewWidth, float viewHeight,
                             TextureLoader* textureLoader)
{
    _modelHomeDir = dir;
    _textureLoader = textureLoader;

    Csm::csmSizeInt size;
    const Csm::csmString path = Csm::csmString(dir) + fileName;

    Csm::csmByte* buffer = CreateBuffer(path.GetRawString(), &size);
    if (buffer == NULL)
    {
        Pal::PrintLogLn("[CubismModel] Failed to load model setting file.");
        return;
    }

    Csm::ICubismModelSetting* setting = new CubismModelSettingJson(buffer, size);
    DeleteBuffer(buffer, path.GetRawString());

    SetupModel(setting);

    if (_model == NULL)
    {
        Pal::PrintLogLn("[CubismModel] Failed to LoadAssets().");
        return;
    }

    CreateRenderer(viewWidth, viewHeight);
    SetupTextures(textureLoader);
}

void CubismModelWrapper::SetupModel(Csm::ICubismModelSetting* setting)
{
    _updating = true;
    _initialized = false;
    _modelSetting = setting;

    Csm::csmByte* buffer;
    Csm::csmSizeInt size;

    if (strcmp(_modelSetting->GetModelFileName(), "") != 0)
    {
        Csm::csmString path = _modelSetting->GetModelFileName();
        path = _modelHomeDir + path;

        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadModel(buffer, size, _mocConsistency);
        DeleteBuffer(buffer, path.GetRawString());
    }

    if (_modelSetting->GetExpressionCount() > 0)
    {
        const Csm::csmInt32 count = _modelSetting->GetExpressionCount();
        for (Csm::csmInt32 i = 0; i < count; i++)
        {
            Csm::csmString name = _modelSetting->GetExpressionName(i);
            Csm::csmString path = _modelSetting->GetExpressionFileName(i);
            path = _modelHomeDir + path;

            buffer = CreateBuffer(path.GetRawString(), &size);
            Csm::ACubismMotion* motion = LoadExpression(buffer, size, name.GetRawString());

            if (motion)
            {
                if (_expressions[name] != NULL)
                {
                    Csm::ACubismMotion::Delete(_expressions[name]);
                    _expressions[name] = NULL;
                }
                _expressions[name] = motion;
            }

            DeleteBuffer(buffer, path.GetRawString());
        }

        CubismExpressionUpdater* expression = CSM_NEW CubismExpressionUpdater(*_expressionManager);
        _updateScheduler.AddUpdatableList(expression);
    }

    if (strcmp(_modelSetting->GetPhysicsFileName(), "") != 0)
    {
        Csm::csmString path = _modelSetting->GetPhysicsFileName();
        path = _modelHomeDir + path;

        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadPhysics(buffer, size);

        if (_physics != NULL)
        {
            CubismPhysicsUpdater* physics = CSM_NEW CubismPhysicsUpdater(*_physics);
            _updateScheduler.AddUpdatableList(physics);
        }

        DeleteBuffer(buffer, path.GetRawString());
    }

    if (strcmp(_modelSetting->GetPoseFileName(), "") != 0)
    {
        Csm::csmString path = _modelSetting->GetPoseFileName();
        path = _modelHomeDir + path;

        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadPose(buffer, size);

        if (_pose != NULL)
        {
            CubismPoseUpdater* pose = CSM_NEW CubismPoseUpdater(*_pose);
            _updateScheduler.AddUpdatableList(pose);
        }

        DeleteBuffer(buffer, path.GetRawString());
    }

    if (_modelSetting->GetEyeBlinkParameterCount() > 0)
    {
        _eyeBlink = CubismEyeBlink::Create(_modelSetting);

        CubismEyeBlinkUpdater* eyeBlink = CSM_NEW CubismEyeBlinkUpdater(_motionUpdated, *_eyeBlink);
        _updateScheduler.AddUpdatableList(eyeBlink);
    }

    {
        _breath = CubismBreath::Create();

        Csm::csmVector<CubismBreath::BreathParameterData> breathParameters;
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleX, 0.0f, 15.0f, 6.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleY, 0.0f, 8.0f, 3.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleZ, 0.0f, 10.0f, 5.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamBodyAngleX, 0.0f, 4.0f, 15.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(
            CubismFramework::GetIdManager()->GetId(ParamBreath), 0.5f, 0.5f, 3.2345f, 0.5f));

        _breath->SetParameters(breathParameters);

        CubismBreathUpdater* breath = CSM_NEW CubismBreathUpdater(*_breath);
        _updateScheduler.AddUpdatableList(breath);
    }

    if (strcmp(_modelSetting->GetUserDataFile(), "") != 0)
    {
        Csm::csmString path = _modelSetting->GetUserDataFile();
        path = _modelHomeDir + path;
        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadUserData(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }

    {
        Csm::csmInt32 eyeBlinkIdCount = _modelSetting->GetEyeBlinkParameterCount();
        for (Csm::csmInt32 i = 0; i < eyeBlinkIdCount; ++i)
        {
            _eyeBlinkIds.PushBack(_modelSetting->GetEyeBlinkParameterId(i));
        }
    }

    {
        Csm::csmInt32 lipSyncIdCount = _modelSetting->GetLipSyncParameterCount();
        for (Csm::csmInt32 i = 0; i < lipSyncIdCount; ++i)
        {
            _lipSyncIds.PushBack(_modelSetting->GetLipSyncParameterId(i));
        }
    }

    {
        _look = CubismLook::Create();

        Csm::csmVector<CubismLook::LookParameterData> lookParameters;
        lookParameters.PushBack(CubismLook::LookParameterData(_idParamAngleX, 30.0f));
        lookParameters.PushBack(CubismLook::LookParameterData(_idParamAngleY, 0.0f, 30.0f));
        lookParameters.PushBack(CubismLook::LookParameterData(_idParamAngleZ, 0.0f, 0.0f, -30.0f));
        lookParameters.PushBack(CubismLook::LookParameterData(_idParamBodyAngleX, 10.0f));
        lookParameters.PushBack(CubismLook::LookParameterData(_idParamEyeBallX, 1.0f));
        lookParameters.PushBack(CubismLook::LookParameterData(_idParamEyeBallY, 0.0f, 1.0f));

        _look->SetParameters(lookParameters);

        CubismLookUpdater* look = CSM_NEW CubismLookUpdater(*_look, *_dragManager);
        _updateScheduler.AddUpdatableList(look);
    }

    _updateScheduler.SortUpdatableList();

    if (_modelSetting == NULL || _modelMatrix == NULL)
    {
        Pal::PrintLogLn("[CubismModel] Failed to SetupModel().");
        return;
    }

    Csm::csmMap<Csm::csmString, Csm::csmFloat32> layout;
    _modelSetting->GetLayoutMap(layout);
    _modelMatrix->SetupFromLayout(layout);

    _model->SaveParameters();

    for (Csm::csmInt32 i = 0; i < _modelSetting->GetMotionGroupCount(); i++)
    {
        const Csm::csmChar* group = _modelSetting->GetMotionGroupName(i);
        PreloadMotionGroup(group);
    }

    _motionManager->StopAllMotions();

    _updating = false;
    _initialized = true;
}

void CubismModelWrapper::PreloadMotionGroup(const Csm::csmChar* group)
{
    const Csm::csmInt32 count = _modelSetting->GetMotionCount(group);

    for (Csm::csmInt32 i = 0; i < count; i++)
    {
        Csm::csmString name = Csm::Utils::CubismString::GetFormatedString("%s_%d", group, i);
        Csm::csmString path = _modelSetting->GetMotionFileName(group, i);
        path = _modelHomeDir + path;

        Csm::csmByte* buffer;
        Csm::csmSizeInt size;
        buffer = CreateBuffer(path.GetRawString(), &size);
        CubismMotion* tmpMotion = static_cast<CubismMotion*>(LoadMotion(buffer, size, name.GetRawString(), NULL, NULL, _modelSetting, group, i));

        if (tmpMotion)
        {
            tmpMotion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);

            if (_motions[name] != NULL)
            {
                Csm::ACubismMotion::Delete(_motions[name]);
            }
            _motions[name] = tmpMotion;
        }

        DeleteBuffer(buffer, path.GetRawString());
    }
}

void CubismModelWrapper::ReleaseMotionGroup(const Csm::csmChar* group) const
{
    const Csm::csmInt32 count = _modelSetting->GetMotionCount(group);
    for (Csm::csmInt32 i = 0; i < count; i++)
    {
        Csm::csmString voice = _modelSetting->GetMotionSoundFileName(group, i);
        if (strcmp(voice.GetRawString(), "") != 0)
        {
            Csm::csmString path = voice;
            path = _modelHomeDir + path;
        }
    }
}

void CubismModelWrapper::ReleaseMotions()
{
    for (Csm::csmMap<Csm::csmString, Csm::ACubismMotion*>::const_iterator iter = _motions.Begin();
         iter != _motions.End(); ++iter)
    {
        Csm::ACubismMotion::Delete(iter->Second);
    }
    _motions.Clear();
}

void CubismModelWrapper::ReleaseExpressions()
{
    for (Csm::csmMap<Csm::csmString, Csm::ACubismMotion*>::const_iterator iter = _expressions.Begin();
         iter != _expressions.End(); ++iter)
    {
        Csm::ACubismMotion::Delete(iter->Second);
    }
    _expressions.Clear();
}

void CubismModelWrapper::ApplyPendingSeek()
{
    if (!_hasPendingSeek) return;
    _hasPendingSeek = false;
    auto* entry = GetLatestMotionEntry();
    if (entry == NULL || !entry->IsStarted()) return;
    entry->SetStartTime(static_cast<Csm::csmFloat32>(_motionQueueTimeSeconds) - _pendingSeekTime);
}

void CubismModelWrapper::Update(float speedMultiplier)
{
    const Csm::csmFloat32 deltaTimeSeconds = Pal::GetDeltaTime() * speedMultiplier;
    _userTimeSeconds += deltaTimeSeconds;
    _motionQueueTimeSeconds += static_cast<double>(deltaTimeSeconds);

    ApplyPendingSeek();

    _motionUpdated = false;

    _model->LoadParameters();
    if (_motionManager->IsFinished())
    {
        if (_loopingEnabled && _lastMotionNo >= 0)
        {
            StartMotion(_lastMotionGroup.GetRawString(), _lastMotionNo, PriorityForce);
        }
        else
        {
            StartRandomMotion(MotionGroupIdle, PriorityIdle);
        }
    }
    _motionUpdated = _motionManager->UpdateMotion(_model, deltaTimeSeconds);
    _model->SaveParameters();

    _opacity = _model->GetModelOpacity();

    _updateScheduler.OnLateUpdate(_model, deltaTimeSeconds);

    _model->Update();
}

Csm::CubismMotionQueueEntryHandle CubismModelWrapper::StartMotion(const Csm::csmChar* group, Csm::csmInt32 no, Csm::csmInt32 priority,
    Csm::ACubismMotion::FinishedMotionCallback onFinishedMotionHandler,
    Csm::ACubismMotion::BeganMotionCallback onBeganMotionHandler)
{
    _lastMotionGroup = group;
    _lastMotionNo = no;

    if (priority == PriorityForce)
    {
        _motionManager->SetReservePriority(priority);
    }
    else if (!_motionManager->ReserveMotion(priority))
    {
        return Csm::InvalidMotionQueueEntryHandleValue;
    }

    const Csm::csmString fileName = _modelSetting->GetMotionFileName(group, no);
    Csm::csmString name = Csm::Utils::CubismString::GetFormatedString("%s_%d", group, no);
    CubismMotion* motion = static_cast<CubismMotion*>(_motions[name.GetRawString()]);
    Csm::csmBool autoDelete = false;

    if (motion == NULL)
    {
        Csm::csmString path = fileName;
        path = _modelHomeDir + path;

        Csm::csmByte* buffer;
        Csm::csmSizeInt size;
        buffer = CreateBuffer(path.GetRawString(), &size);
        motion = static_cast<CubismMotion*>(LoadMotion(buffer, size, NULL, onFinishedMotionHandler, NULL, _modelSetting, group, no));

        if (motion)
        {
            motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
            autoDelete = true;
        }

        DeleteBuffer(buffer, path.GetRawString());
    }
    else
    {
        motion->SetBeganMotionHandler(onBeganMotionHandler);
        motion->SetFinishedMotionHandler(onFinishedMotionHandler);
    }

    return _motionManager->StartMotionPriority(motion, autoDelete, priority);
}

Csm::CubismMotionQueueEntryHandle CubismModelWrapper::StartRandomMotion(const Csm::csmChar* group, Csm::csmInt32 priority,
    Csm::ACubismMotion::FinishedMotionCallback onFinishedMotionHandler,
    Csm::ACubismMotion::BeganMotionCallback onBeganMotionHandler)
{
    if (_modelSetting->GetMotionCount(group) == 0)
    {
        return Csm::InvalidMotionQueueEntryHandleValue;
    }

    Csm::csmInt32 no = rand() % _modelSetting->GetMotionCount(group);
    return StartMotion(group, no, priority, onFinishedMotionHandler, onBeganMotionHandler);
}

void CubismModelWrapper::DoDraw()
{
    if (_model == NULL) return;
    GetRenderer<Rendering::CubismRenderer_Metal>()->DrawModel();
}

void CubismModelWrapper::Draw(Csm::CubismMatrix44& matrix)
{
    if (_model == NULL) return;
    matrix.MultiplyByMatrix(_modelMatrix);
    GetRenderer<Rendering::CubismRenderer_Metal>()->SetMvpMatrix(&matrix);
    DoDraw();
}

Csm::csmBool CubismModelWrapper::HitTest(const Csm::csmChar* hitAreaName, Csm::csmFloat32 x, Csm::csmFloat32 y)
{
    if (_opacity < 1) return false;

    const Csm::csmInt32 count = _modelSetting->GetHitAreasCount();
    for (Csm::csmInt32 i = 0; i < count; i++)
    {
        if (strcmp(_modelSetting->GetHitAreaName(i), hitAreaName) == 0)
        {
            const Csm::CubismIdHandle drawID = _modelSetting->GetHitAreaId(i);
            return IsHit(drawID, x, y);
        }
    }
    return false;
}

void CubismModelWrapper::SetExpression(const Csm::csmChar* expressionID)
{
    Csm::ACubismMotion* motion = _expressions[expressionID];
    if (motion != NULL)
    {
        _expressionManager->StartMotion(motion, false);
    }
}

void CubismModelWrapper::SetRandomExpression()
{
    if (_expressions.GetSize() == 0) return;

    Csm::csmInt32 no = rand() % _expressions.GetSize();
    Csm::csmMap<Csm::csmString, Csm::ACubismMotion*>::const_iterator map_ite;
    Csm::csmInt32 i = 0;
    for (map_ite = _expressions.Begin(); map_ite != _expressions.End(); map_ite++)
    {
        if (i == no)
        {
            Csm::csmString name = (*map_ite).First;
            SetExpression(name.GetRawString());
            return;
        }
        i++;
    }
}

void CubismModelWrapper::ReloadRenderer(float viewWidth, float viewHeight, TextureLoader* textureLoader)
{
    DeleteRenderer();
    CreateRenderer(viewWidth, viewHeight);
    SetupTextures(textureLoader);
}

void CubismModelWrapper::SetupTextures(TextureLoader* textureLoader)
{
    for (Csm::csmInt32 modelTextureNumber = 0; modelTextureNumber < _modelSetting->GetTextureCount(); modelTextureNumber++)
    {
        if (!strcmp(_modelSetting->GetTextureFileName(modelTextureNumber), ""))
        {
            continue;
        }

        Csm::csmString texturePath = _modelSetting->GetTextureFileName(modelTextureNumber);
        texturePath = _modelHomeDir + texturePath;

        TextureInfo* textureInfo = [textureLoader createTextureFromPngFile:texturePath.GetRawString()];
        if (textureInfo == NULL)
        {
            continue;
        }

        GetRenderer<Rendering::CubismRenderer_Metal>()->BindTexture(modelTextureNumber, textureInfo->texture);
    }

    GetRenderer<Rendering::CubismRenderer_Metal>()->IsPremultipliedAlpha(false);
}

void CubismModelWrapper::SetDragPosition(Csm::csmFloat32 x, Csm::csmFloat32 y)
{
    _dragManager->Set(x, y);
}

void CubismModelWrapper::SetPhysicsEnabled(Csm::csmBool enabled)
{
    _physicsEnabled = enabled;
}

CubismMotionQueueEntry* CubismModelWrapper::GetLatestMotionEntry()
{
    auto* entries = _motionManager->GetCubismMotionQueueEntries();
    if (entries == NULL || entries->GetSize() == 0) return NULL;
    return (*entries)[entries->GetSize() - 1];
}

Csm::csmFloat32 CubismModelWrapper::GetCurrentMotionTime()
{
    auto* entry = GetLatestMotionEntry();
    if (entry == NULL || !entry->IsStarted()) return 0.0f;

    double elapsed = _motionQueueTimeSeconds - static_cast<double>(entry->GetStartTime());
    auto* motion = entry->GetCubismMotion();
    if (motion == NULL) return static_cast<float>(fmax(elapsed, 0.0));

    float duration = motion->GetDuration();
    if (duration <= 0) return static_cast<float>(fmax(elapsed, 0.0));
    return static_cast<float>(fmod(fmax(elapsed, 0.0), static_cast<double>(duration)));
}

Csm::csmFloat32 CubismModelWrapper::GetCurrentMotionDuration()
{
    auto* entry = GetLatestMotionEntry();
    if (entry == NULL) return 0.0f;

    auto* motion = entry->GetCubismMotion();
    if (motion == NULL) return 0.0f;
    return motion->GetDuration();
}

void CubismModelWrapper::SeekMotionTo(Csm::csmFloat32 time)
{
    _pendingSeekTime = time;
    _hasPendingSeek = true;
}

void CubismModelWrapper::SetLoopingEnabled(Csm::csmBool enabled)
{
    _loopingEnabled = enabled;
}

Csm::csmBool CubismModelWrapper::IsLoopingEnabled() const
{
    return _loopingEnabled;
}

void CubismModelWrapper::MotionEventFired(const Live2D::Cubism::Framework::csmString& eventValue)
{
    Pal::PrintLogLn("[CubismModel] motion event: %s", eventValue.GetRawString());
}

Csm::csmBool CubismModelWrapper::HasMocConsistencyFromFile(const Csm::csmChar* mocFileName)
{
    Csm::csmSizeInt size;
    Csm::csmByte* buffer = Pal::LoadFileAsBytes(mocFileName, &size);
    Csm::csmBool consistency = CubismMoc::HasMocConsistency(buffer, size);
    Pal::ReleaseBytes(buffer);
    return consistency;
}

Rendering::CubismRenderTarget_Metal& CubismModelWrapper::GetRenderBuffer()
{
    return _renderBuffer;
}
