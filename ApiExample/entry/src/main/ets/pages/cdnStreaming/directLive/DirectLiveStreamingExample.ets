import {
  QNCameraVideoTrack,
  QNCameraVideoTrackConfig,
  QNClientEventListener,
  QNComponentController,
  QNConnectionDisconnectedInfo,
  QNConnectionState,
  QNCustomMessage,
  QNDegradationPreference,
  QNDirectLiveStreamingConfig,
  QNErrorCode,
  QNLiveStreamingErrorInfo,
  QNLocalTrack,
  QNLogConfig,
  QNMicrophoneAudioTrack,
  QNMicrophoneAudioTrackConfig,
  QNMicrophoneEventListener,
  QNRemoteAudioTrack,
  QNRemoteTrack,
  QNRemoteVideoTrack,
  QNRTC,
  QNRTCClient,
  QNRTCClientConfig,
  QNRTCSetting,
  QNStretchMode,
  QNVideoCaptureConfig,
  QNVideoEncoderConfig
} from "@qiniu/qnrtckit"
import { scanBarcode, scanCore } from "@kit.ScanKit"
import { promptAction } from "@kit.ArkUI"
import { wantAgent, WantAgent } from "@kit.AbilityKit"
import { BusinessError } from "@kit.BasicServicesKit"
import { backgroundTaskManager } from "@kit.BackgroundTasksKit"
import { util } from "@kit.ArkTS"
import { QNLiveStreamingListener } from "@qiniu/qnrtckit"
import { Constants } from "../../../common/Constants"

/**
 * 1v1 音视频通话 + 单路转推场景
 *
 * 主要步骤如下：
 * 1. 初始化 RTC
 * 2. 创建 QNRTCClient 对象
 * 3. 设置 CDN 转推事件监听器
 * 4. 创建本地音视频 Track 并关联渲染视图
 * 5. 加入房间
 * 6. 发布本地音视频 Track（发布后可创建基于本地音视频 Track 的转推任务）
 * 7. 订阅远端音视频 Track（订阅后可创建基于远端音视频 Track 的转推任务）
 * 8. 离开房间
 * 9. 反初始化 RTC 释放资源
 *
 * 文档参考：
 * - CDN 转推使用指南，请参考 https://developer.qiniu.com/rtc/12843/solution_streaming-HarmonyOS
 */

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
export struct DirectLiveStreamingExample {
  @Consume('pathStack') pathInfos: NavPathStack
  private token: string = ""
  private client: QNRTCClient | null = null
  private micTrack: QNMicrophoneAudioTrack | null = null
  private localTracks: QNLocalTrack[] = []
  private cameraTrack: QNCameraVideoTrack | null = null
  private config: QNDirectLiveStreamingConfig | null = null
  private localRenderComponentCtrl: QNComponentController = new QNComponentController()
  private remoteRenderComponentCtrl: QNComponentController = new QNComponentController()
  private connectionState: QNConnectionState = QNConnectionState.Disconnected
  private willHide: boolean = false
  private recordingStopped: boolean = false
  @State publishUrl: string = ""
  @State localRenderVisibility: Visibility = Visibility.Hidden
  @State remoteRenderVisibility: Visibility = Visibility.Hidden
  /**
   * 房间事件监听回调
   */
  private clientListener: QNClientEventListener = {
    OnConnectionStateChanged: (state: QNConnectionState, info: QNConnectionDisconnectedInfo) => {
      this.connectionState = state
      if (state == QNConnectionState.Connected) {
        // 发布本地音视频 Track
        if (this.client) {
          this.client.Publish(this.localTracks, null)
        }
      }
    },
    OnSubscribed: (userid: string, remoteAudioTrackList: QNRemoteAudioTrack[],
      remoteVideoTrackList: QNRemoteVideoTrack[]) => {
      if (remoteVideoTrackList.length) {
        let remoteVideoTrack: QNRemoteVideoTrack = remoteVideoTrackList[0]
        // 设置远端渲染视图
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
  /**
   * 麦克风事件监听回调
   */
  private microphoneEventListener: QNMicrophoneEventListener = {
    OnError: (errorCode: number, message: string) => {
      if (errorCode == QNErrorCode.MicCaptureFailed) {
        this.recordingStopped = true
        // 麦克风出现错误，执行 StopRecording 释放相关资源
        this.micTrack?.StopRecording()
      }
    }
  }
  /**
   * 转推任务监听回调
   */
  private liveStreamingListener: QNLiveStreamingListener = {
    OnStarted: (streamID: string): void => {
      promptAction.showToast({
        message: `任务 ${streamID} 开始转推`
      })
    },
    OnStopped: (streamID: string): void => {
      promptAction.showToast({
        message: `任务 ${streamID} 已停止转推`
      })
    },
    OnTranscodingTracksUpdated: (streamID: string): void => {

    },
    OnError: (streamID: string, info: QNLiveStreamingErrorInfo): void => {
      promptAction.showToast({
        message: `任务 ${streamID} 出现错误：${info.type}, ${info.code}, ${info.message}`
      })
    }
  }

  aboutToAppear(): void {
    this.initRtcClient()
    this.join()
  }

  aboutToDisappear(): void {
    if (this.client && this.connectionState == QNConnectionState.Connected) {
      // 离开房间
      this.client!.Leave()
    }
    // 反初始化 RTC 释放资源
    QNRTC.DeInit()
  }

  initRtcClient(): void {
    // 设置日志等级
    let logConfig: QNLogConfig = new QNLogConfig()
    logConfig.dir = getContext(this).filesDir
    logConfig.logLevel = 2
    QNRTC.SetLogConfig(logConfig)
    // 初始化 RTC
    let setting: QNRTCSetting = new QNRTCSetting()
    let ret: number = QNRTC.Init(setting)
    // 创建 QNRTCClient
    this.client = QNRTC.CreateClient(new QNRTCClientConfig())
    this.client!.SetClientEventListener(this.clientListener)
    // 设置 CDN 转推事件监听器
    this.client?.SetLiveStreamingListener(this.liveStreamingListener)
    // 创建麦克风采集 Track
    this.micTrack = QNRTC.CreateMicrophoneAudioTrack(new QNMicrophoneAudioTrackConfig())
    if (this.micTrack != null) {
      this.micTrack.SetMicrophoneEventListener(this.microphoneEventListener)
    }
    // 创建摄像头采集 Track
    let videoTrackConfig: QNCameraVideoTrackConfig = new QNCameraVideoTrackConfig()
    // 配置视频采集参数
    let videoCaptureConfig: QNVideoCaptureConfig = new QNVideoCaptureConfig()
    videoCaptureConfig.width = Constants.DEFAULT_CAPTURE_WIDTH
    videoCaptureConfig.height = Constants.DEFAULT_CAPTURE_HEIGHT
    videoCaptureConfig.frameRate = Constants.DEFAULT_CAPTURE_FPS
    // 配置视频编码参数
    let videoEncodeConfig: QNVideoEncoderConfig = new QNVideoEncoderConfig()
    videoEncodeConfig.width = Constants.DEFAULT_ENCODE_WIDTH
    videoEncodeConfig.height = Constants.DEFAULT_ENCODE_HEIGHT
    videoEncodeConfig.frameRate = Constants.DEFAULT_ENCODE_FPS
    videoEncodeConfig.bitrate = Constants.DEFAULT_VIDEO_ENCODE_BITRATE
    videoEncodeConfig.prefer = QNDegradationPreference.MaintainResolution
    videoTrackConfig.encoderConfig = videoEncodeConfig
    videoTrackConfig.captureConfig = videoCaptureConfig
    this.cameraTrack = QNRTC.CreateCameraVideoTrack(videoTrackConfig)

    if (this.micTrack) {
      this.localTracks.push(this.micTrack)
    }
    if (this.cameraTrack) {
      this.localTracks.push(this.cameraTrack)
    }
  }

  /**
   * 加入房间
   */
  join(): void {
    // 获取 token
    // token 生成规则：https://developer.qiniu.com/rtc/8813/roomToken
    // 通过控制台获取 token：https://developer.qiniu.com/rtc/9858/applist#4
    let styledString: MutableStyledString = new MutableStyledString(JSON.stringify(this.pathInfos.getParamByIndex(0)))
    styledString.removeString(0, 1)
    styledString.removeString(styledString.length - 1, 1)
    this.token = styledString.getString()
    // 加房
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
              console.log("local surfaceId", this.localRenderComponentCtrl.getXComponentSurfaceId())
            }).paddingStyle().align(Alignment.Center).visibility(this.localRenderVisibility)
          }
          .width('50%')
          .height('100%')
          .margin('1')
          .renderViewStyle()
          .backgroundColor($r('app.color.view_background'))

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
              console.log("remote surfaceId: ", this.remoteRenderComponentCtrl.getXComponentSurfaceId())
            }).paddingStyle().align(Alignment.Center).visibility(this.remoteRenderVisibility)
          }
          .width('50%')
          .height('100%')
          .margin('1')
          .renderViewStyle()
          .backgroundColor($r('app.color.view_background'))
        }.width('100%').height('40%')

        Column() {
          Row() {
            Text('转推地址：')
            Image('resources/base/media/scan.png')
              .width(48)
              .height(48)
              .padding(10)
              .onClick(() => {
                // 定义扫码参数options
                let options: scanBarcode.ScanOptions = {
                  scanTypes: [scanCore.ScanType.ALL],
                  enableMultiMode: true,
                  enableAlbum: true
                }
                try {
                  // 可调用getContext接口获取当前页面关联的UIAbilityContext
                  scanBarcode.startScanForResult(getContext(this), options).then((result: scanBarcode.ScanResult) => {
                    // 解析码值结果跳转应用服务页
                    console.info(`Succeeded in getting ScanResult by promise with options, result is ${result.originalValue}`)
                    if (result.originalValue) {
                      this.publishUrl = result.originalValue
                    } else {
                      promptAction.showToast({
                        message: '获取推流地址失败',
                        duration: 2000
                      })
                    }
                  }).catch((error: BusinessError) => {
                    console.error(`Failed to get ScanResult by promise with options. Code:${error.code}, message: ${error.message}`)
                  })
                } catch (error) {
                  console.error(`Failed to start the scanning service. Code:${error.code}, message: ${error.message}`)
                }
              })
          }
          .width('100%')

          TextInput({ text: this.publishUrl, placeholder: '自定义转推 rtmp 地址' })

          Row() {
            Button('开始转推')
              .onClick(() => {
                if (this.publishUrl == '') {
                  promptAction.showToast({
                    message: '非法推流地址'
                  })
                  return
                }
                // 创建并开始单路转推
                this.config = new QNDirectLiveStreamingConfig()
                this.config.publishUrl = this.publishUrl
                this.config.localAudioTrack = this.micTrack
                this.config.localVideoTrack = this.cameraTrack
                this.config.streamId = util.generateRandomUUID()
                this.client?.StartLiveStreaming(this.config)
              }).margin(8).width('40%')
            Button('停止转推')
              .onClick(() => {
                // 停止单路转推
                this.client?.StopLiveStreaming(this.config)
              }).margin(8).width('40%')
          }
          .margin({ top: 16 })
        }
        .width('100%')
        .height('50%')
        .padding(16)
        .justifyContent(FlexAlign.Start)
        .backgroundColor($r('app.color.view_background'))
        .borderRadius(10)

        Row() {
          Text("Tips：本示例仅展示一对一场景下本地或远端音视频 Track 的单路转推功能，该转推经由 RTC 服务端转推实现，使用转推功能需要在七牛后台开启对应 AppId 的转推功能开关。")
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
    .title('CDN 单人转推')
    .onShown(() => {
      console.info('onShown')
      this.cameraTrack?.StartCapture()
      // 设置渲染视图
      if (this.localRenderVisibility != Visibility.Visible) {
        this.cameraTrack?.Play(this.localRenderComponentCtrl, QNStretchMode.StretchFill)
        this.localRenderVisibility = Visibility.Visible
      }
      if (this.recordingStopped) {
        // 麦克风出现错误的场景（如电话打断等），需要重新开启麦克风采集
        this.micTrack?.StartRecording()
        this.recordingStopped = false
      }
      this.stopBackgroundAudioRecording()
    })
    .onHidden(() => {
      console.info('onHidden')
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