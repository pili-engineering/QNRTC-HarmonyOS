import { hilog } from '@kit.PerformanceAnalysisKit'

import {
  QNRTC,
  QNRTCSetting,
  QNLogConfig,
  QNMicrophoneAudioTrackConfig,
  QNRTCClientConfig,
  QNRTCClient,
  QNMicrophoneAudioTrack,
  QNLocalTrack,
  QNCameraVideoTrack,
  QNRemoteVideoTrack,
  QNCameraVideoTrackConfig,
  QNRemoteAudioTrack,
  QNRemoteTrack,
  QNClientEventListener,
  QNConnectionState,
  QNConnectionDisconnectedInfo,
  QNVideoCaptureConfig,
  QNVideoEncoderConfig,
  QNComponentController,
  QNStretchMode,
  QNCustomMessage,
  QNMicrophoneEventListener,
  QNErrorCode
} from '@qiniu/qnrtckit'
import { WantAgent, wantAgent } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'

@Styles
function paddingStyle() {
  .width('100%')
  .height('100%')
  .borderRadius(5)
  .backgroundColor(Color.White)
}

@Styles
function renderViewStyle() {
  .width('50%')
  .height('50%')
  .aspectRatio(3.0 / 4)
  .borderRadius(5)
  .backgroundColor($r('app.color.view_background'))
}

@Component
export struct CameraVideoExample {
  @Consume('pathStack') pathInfos: NavPathStack
  private token: string = ""
  private client: QNRTCClient | null = null
  private micTrack: QNMicrophoneAudioTrack | null = null
  private localTracks: QNLocalTrack[] = []
  private cameraTrack: QNCameraVideoTrack | null = null
  private localRenderComponentCtrl: QNComponentController = new QNComponentController()
  private remoteRenderComponentCtrl: QNComponentController = new QNComponentController()
  private connectionState: QNConnectionState = QNConnectionState.Disconnected
  private willHide: boolean = false
  private recordingStopped: boolean = false
  @State localRenderVisibility: Visibility = Visibility.Hidden
  @State remoteRenderVisibility: Visibility = Visibility.Hidden
  private clientListener: QNClientEventListener = {
    OnConnectionStateChanged: (state: QNConnectionState, info: QNConnectionDisconnectedInfo) => {
      this.connectionState = state
      if (state == QNConnectionState.Connected) {
        // set local render
        this.cameraTrack!.Play(this.localRenderComponentCtrl, QNStretchMode.StretchFill)
        this.localRenderVisibility = Visibility.Visible
        // publish local tracks
        if (this.client) {
          this.client.Publish(this.localTracks, null)
        }
      }
    },
    OnSubscribed: (userid: string, remoteAudioTrackList: QNRemoteAudioTrack[],
      remoteVideoTrackList: QNRemoteVideoTrack[]) => {
      if (remoteVideoTrackList.length) {
        let remoteVideoTrack: QNRemoteVideoTrack = remoteVideoTrackList[0]
        // set remote render
        remoteVideoTrack.Play(this.remoteRenderComponentCtrl, QNStretchMode.StretchFill)
        this.remoteRenderVisibility = Visibility.Visible
      }
    },
    OnUserJoined: (remoteUserId: string, userData: string) => {
      console.log("OnUserJoined: ", remoteUserId)
    },
    OnUserLeft: (remoteUserId: string) => {
      console.log("OnUserLeft: ", remoteUserId)
    },
    OnUserReconnecting: (remoteUserId: string) => {
      console.log("OnUserReconnecting: ", remoteUserId)
    },
    OnUserReconnected: (remoteUserId: string) => {
      console.log("OnUserReconnected: ", remoteUserId)
    },
    OnUserPublished: (remoteUserId: string, remoteTrackList: QNRemoteTrack[]) => {
      console.log("OnUserPublished: ", remoteUserId)
    },
    OnUserUnpublished: (remoteUserId: string, remoteTrackList: QNRemoteTrack[]) => {
      console.log("OnUserUnpublished: ", remoteUserId)
    },
    OnMessageReceived: (message: QNCustomMessage) => {
      console.log("OnMessageReceived: ", message)
    }
  }

  private microphoneEventListener: QNMicrophoneEventListener = {
    OnError: (errorCode: number, message: string) => {
      if (errorCode == QNErrorCode.MicCaptureFailed) {
        this.recordingStopped = true
        // 麦克风出现错误，执行 StopRecording 释放相关资源
        this.micTrack?.StopRecording()
      }
    }
  }

  aboutToAppear(): void {
    this.initRtcClient()
    this.join()
  }

  aboutToDisappear(): void {
    if (this.client && this.connectionState == QNConnectionState.Connected) {
      this.client!.Leave()
    }
    QNRTC.DeInit()
  }

  initRtcClient(): void {
    // set log
    let logConfig: QNLogConfig = new QNLogConfig()
    logConfig.dir = getContext(this).filesDir
    logConfig.logLevel = 2
    QNRTC.SetLogConfig(logConfig)
    // init rtc
    let setting: QNRTCSetting = new QNRTCSetting()
    let ret: number = QNRTC.Init(setting)
    // create rtc client
    this.client = QNRTC.CreateClient(new QNRTCClientConfig())
    this.client!.SetClientEventListener(this.clientListener)
    // create track
    this.micTrack = QNRTC.CreateMicrophoneAudioTrack(new QNMicrophoneAudioTrackConfig())
    if (this.micTrack != null) {
      this.micTrack.SetMicrophoneEventListener(this.microphoneEventListener)
    }
    let videoTrackConfig: QNCameraVideoTrackConfig = new QNCameraVideoTrackConfig()
    let videoCaptureConfig: QNVideoCaptureConfig = new QNVideoCaptureConfig()
    let videoEncodeConfig: QNVideoEncoderConfig = new QNVideoEncoderConfig()
    videoTrackConfig.encoderConfig = videoEncodeConfig
    videoTrackConfig.captureConfig = videoCaptureConfig
    this.cameraTrack = QNRTC.CreateCameraVideoTrack(videoTrackConfig)
    // set local track
    if (this.micTrack) {
      this.localTracks.push(this.micTrack)
    }
    if (this.cameraTrack) {
      this.localTracks.push(this.cameraTrack)
    }
  }

  join(): void {
    // get token
    let styledString: MutableStyledString = new MutableStyledString(JSON.stringify(this.pathInfos.getParamByIndex(0)))
    styledString.removeString(0, 1)
    styledString.removeString(styledString.length - 1, 1)
    this.token = styledString.getString()
    // join room
    this.client!.Join(this.token)
  }

  /**
   * 启动后台长时任务，用于后台音频采集
   */
  startBackgroundAudioRecording() {
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: "com.qiniu.apiexample",
          abilityName: "EntryAbility"
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }

    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(getContext(this),
        backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, wantAgentObj).then(() => {
        console.info(`Succeeded in operationing startBackgroundRunning.`)
      }).catch((err: BusinessError) => {
        console.error(`Failed to operation startBackgroundRunning. Code is ${err.code}, message is ${err.message}`)
      })
    })
  }

  /**
   * 停止后台长时任务
   */
  stopBackgroundAudioRecording() {
    backgroundTaskManager.stopBackgroundRunning(getContext(this)).then(() => {
      console.info(`Succeeded in operationing stopBackgroundRunning.`)
    }).catch((err: BusinessError) => {
      console.error(`Failed to operation stopBackgroundRunning. Code is ${err.code}, message is ${err.message}`)
    })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Stack() {
            Text("本地视图")
              .textAlign(TextAlign.Center)
              .fontColor(Color.Black)
              .align(Alignment.Center)
              .fontSize(18)
              .width('100%')
              .height('100%')

            XComponent({
              type: XComponentType.SURFACE,
              controller: this.localRenderComponentCtrl
            }).onLoad(() => {
              console.log("local surfaceid", this.localRenderComponentCtrl.getXComponentSurfaceId())
            }).paddingStyle().align(Alignment.Center).visibility(this.localRenderVisibility)
          }
          .width('50%')
          .height('100%')
          .margin('1')
          .renderViewStyle()

          Stack() {
            Text("远端视图")
              .textAlign(TextAlign.Center)
              .fontColor(Color.Black)
              .align(Alignment.Center)
              .fontSize(18)
              .width('100%')
              .height('100%')

            XComponent({
              type: XComponentType.SURFACE,
              controller: this.remoteRenderComponentCtrl
            }).onLoad(() => {
              console.log("remote surfaceid: ", this.remoteRenderComponentCtrl.getXComponentSurfaceId())
            }).paddingStyle().align(Alignment.Center).visibility(this.remoteRenderVisibility)
          }
          .width('50%')
          .height('100%')
          .margin('1')
          .renderViewStyle()
        }.width('100%').height('40%')

        Row() {
          // todo
        }
        .width('100%')
        .height('50%')
        .padding(5)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.view_background'))
        .borderRadius(10)

        Row() {
          Text("Tips: 本示例仅展示一对一场景下 SDK 内置摄像头采集视频 Track 和麦克风采集音频 Track 的发布和订阅")
            .textAlign(TextAlign.Start)
            .fontColor(Color.Black)
            .align(Alignment.Bottom)
            .fontSize(13)
            .padding(3)
        }
        .width('100%')
        .height('10%')
        .padding(5)
        .justifyContent(FlexAlign.End)
      }
    }
    .title('音视频通话')
    .onShown(() => {
      this.cameraTrack?.StartCapture()
      if (this.recordingStopped) {
        // 麦克风出现错误的场景（如电话打断等），需要重新开启麦克风采集
        this.micTrack?.StartRecording()
        this.recordingStopped = false
      }
      this.stopBackgroundAudioRecording()
    })
    .onHidden(() => {
      // 鸿蒙不支持后台摄像头采集，退后台时需要主动停止摄像头采集，否则会出现崩溃
      this.cameraTrack?.StopCapture()
      if (!this.willHide) {
        // 鸿蒙后台麦克风采集需要创建并开启长时任务
        // 详情可参考 https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/continuous-task-0000001774280022
        this.startBackgroundAudioRecording()
      }
    })
    .onWillShow(() => {
      this.willHide = false
    })
    .onWillHide(() => {
      this.willHide = true
    })
  }
}