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
  QNLocalAudioTrackStats,
  QNLocalTrack,
  QNLocalVideoTrackStats,
  QNLogConfig,
  QNMicrophoneAudioTrack,
  QNMicrophoneAudioTrackConfig,
  QNMicrophoneEventListener,
  QNNetworkGrade,
  QNNetworkQuality,
  QNNetworkQualityListener,
  QNRemoteAudioTrack,
  QNRemoteAudioTrackStats,
  QNRemoteTrack,
  QNRemoteVideoTrack,
  QNRemoteVideoTrackStats,
  QNRTC,
  QNRTCClient,
  QNRTCClientConfig,
  QNRTCSetting,
  QNStretchMode,
  QNVideoCaptureConfig,
  QNVideoEncoderConfig
} from "@qiniu/qnrtckit";
import { wantAgent, WantAgent } from "@kit.AbilityKit"
import { BusinessError } from "@kit.BasicServicesKit"
import { backgroundTaskManager } from "@kit.BackgroundTasksKit"
import { HashMap } from "@kit.ArkTS"
import { Constants } from "../../common/Constants"

/**
 * 1v1 音视频通话 + 通话质量信息统计场景
 *
 * 主要步骤如下：
 * 1. 初始化 RTC
 * 2. 创建 QNRTCClient 对象
 * 3. 创建本地音视频 Track
 * 4. 加入房间
 * 5. 发布本地音视频 Track
 * 6. 订阅远端音视频 Track
 * 7. 开启通话质量统计
 * 8. 离开房间
 * 9. 反初始化 RTC 释放资源
 *
 * 文档参考：
 * - 通话信息统计文档，请参考 https://developer.qiniu.com/rtc/12844/statistics-HarmonyOS
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

@Styles
function statisticsTitleStyle() {
  .width('50%')
  .padding({ left: 16 })
}

@Component
export struct MediaStatisticsExample {
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
  private intervalId: number = 0
  @State localRenderVisibility: Visibility = Visibility.Hidden
  @State remoteRenderVisibility: Visibility = Visibility.Hidden
  @State localUplinkNetworkGrade: QNNetworkGrade = QNNetworkGrade.Invalid
  @State localDownlinkNetworkGrade: QNNetworkGrade = QNNetworkGrade.Invalid
  @State localUplinkAudioBitrate: number = 0
  @State localUplinkAudioRtt: number = 0
  @State localUplinkAudioLostRate: number = 0
  @State localUplinkVideoFps: number = 0
  @State localUplinkVideoBitrate: number = 0
  @State localUplinkVideoRtt: number = 0
  @State localUplinkVideoLostRate: number = 0
  @State remoteUplinkNetworkGrade: QNNetworkGrade = QNNetworkGrade.Invalid
  @State remoteDownlinkNetworkGrade: QNNetworkGrade = QNNetworkGrade.Invalid
  @State remoteDownlinkAudioBitrate: number = 0
  @State remoteDownlinkAudioLostRate: number = 0
  @State remoteUplinkAudioRtt: number = 0
  @State remoteUplinkAudioLostRate: number = 0
  @State remoteDownlinkVideoFps: number = 0
  @State remoteDownlinkVideoBitrate: number = 0
  @State remoteDownlinkVideoLostRate: number = 0
  @State remoteUplinkVideoRtt: number = 0
  @State remoteUplinkVideoLostRate: number = 0
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
          // 开始通话质量统计
          this.startStatisticsInterval()
        }
      } else if (state == QNConnectionState.Disconnected) {
        // 停止通话质量统计
        this.stopStatisticsInterval()
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
   * 网络质量监听回调
   */
  private networkQualityListener: QNNetworkQualityListener = {
    OnNetworkQualityNotified: (quality: QNNetworkQuality) => {
      if (quality.downlink_network_grade != QNNetworkGrade.Invalid ||
        quality.uplink_network_grade != QNNetworkGrade.Invalid) {
        this.localUplinkNetworkGrade = quality.uplink_network_grade
        this.localDownlinkNetworkGrade = quality.downlink_network_grade
      }
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
    this.client?.SetNetworkQualityListener(this.networkQualityListener)
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
   * 开始通话质量统计
   */
  startStatisticsInterval() {
    if (this.intervalId != 0) {
      return
    }
    this.intervalId = setInterval(() => {
      // 本地音频 Track 统计信息
      let audioStatsMap: HashMap<string, QNLocalAudioTrackStats> = this.client!.GetLocalAudioTrackStats()
      if (!audioStatsMap.isEmpty()) {
        audioStatsMap.forEach((value: QNLocalAudioTrackStats, key?: string) => {
          this.localUplinkAudioBitrate = value.uplinkBitrate
          this.localUplinkAudioRtt = value.uplinkRtt
          this.localUplinkAudioLostRate = value.uplinkLostrate
        })
      }
      // 本地视频 Track 统计信息
      let videoStatsMap: HashMap<string, QNLocalVideoTrackStats[]> = this.client!.GetLocalVideoTrackStats()
      videoStatsMap.forEach((list?: QNLocalVideoTrackStats[], key?: string) => {
        if (list != undefined) {
          list.forEach((stats: QNLocalVideoTrackStats, index?: number) => {
            this.localUplinkVideoFps = stats.uplinkFramerate
            this.localUplinkVideoBitrate = stats.uplinkBitrate
            this.localUplinkVideoRtt = stats.uplinkRtt
            this.localUplinkVideoLostRate = stats.uplinkLostrate
          })
        }
        // remote audio stats
        let remoteAudioStatsMap: HashMap<string, QNRemoteAudioTrackStats> = this.client!.GetRemoteAudioTrackStats()
        if (!remoteAudioStatsMap.isEmpty()) {
          remoteAudioStatsMap.forEach((value: QNRemoteAudioTrackStats, key?: string) => {
            this.remoteUplinkAudioRtt = value.uplinkRtt
            this.remoteUplinkAudioLostRate = value.uplinkLostrate
            this.remoteDownlinkAudioBitrate = value.downlinkBitrate
            this.remoteDownlinkAudioLostRate = value.downlinkLostrate
          })
        }
        // remote Video stats
        let remoteVideoStatsMap: HashMap<string, QNRemoteVideoTrackStats> = this.client!.GetRemoteVideoTrackStats()
        if (!remoteVideoStatsMap.isEmpty()) {
          remoteVideoStatsMap.forEach((value: QNRemoteVideoTrackStats, key?: string) => {
            this.remoteUplinkVideoRtt = value.uplinkRtt
            this.remoteUplinkVideoLostRate = value.uplinkLostrate
            this.remoteDownlinkVideoFps = value.downlinkFramerate
            this.remoteDownlinkVideoBitrate = value.downlinkBitrate
            this.remoteDownlinkVideoLostRate = value.downlinkLostrate
          })
        }
      })
    }, 3000)
  }

  /**
   * 停止通话质量统计
   */
  stopStatisticsInterval() {
    clearInterval(this.intervalId)
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

        Scroll() {
          Column({ space: 12 }) {
            Row() {
              Text('本地上行网络质量：').statisticsTitleStyle()
              Text(`${QNNetworkGrade[this.localUplinkNetworkGrade]}`)
                .width('50%')
                .fontSize(14)
                .textAlign(TextAlign.Start)
                .fontColor($r('app.color.light_blue'))
            }

            Row() {
              Text('本地下行网络质量：').statisticsTitleStyle()
              Text(`${QNNetworkGrade[this.localDownlinkNetworkGrade]}`)
                .width('50%')
                .fontSize(14)
                .textAlign(TextAlign.Start)
                .fontColor($r('app.color.light_blue'))
            }

            Row() {
              Text('本地音频 Track 质量：').statisticsTitleStyle()
              Text('远端音频 Track 质量：').statisticsTitleStyle()
            }

            Row() {
              Column({ space: 4 }) {
                Row() {
                  Text('上行码率: ').fontSize(14)
                  Text(`${Math.ceil(this.localUplinkAudioBitrate / 1024)} kbps`)
                    .fontColor($r('app.color.light_blue'))
                    .fontSize(14)
                }

                Row() {
                  Text('上行网络延时: ').fontSize(14)
                  Text(`${this.localUplinkAudioRtt} ms`).fontColor($r('app.color.light_blue')).fontSize(14)
                }

                Row() {
                  Text('上行丢包率: ').fontSize(14)
                  Text(`${this.localUplinkAudioLostRate}%`).fontColor($r('app.color.light_blue')).fontSize(14)
                }
              }
              .width('50%')
              .margin({ left: 24 })
              .alignItems(HorizontalAlign.Start)

              Column({ space: 4 }) {
                Row() {
                  Text('下行码率: ').fontSize(14)
                  Text(`${Math.ceil(this.remoteDownlinkVideoBitrate / 1024)} kbps`)
                    .fontColor($r('app.color.light_blue'))
                    .fontSize(14)
                }

                Row() {
                  Text('下行丢包率: ').fontSize(14)
                  Text(`${this.remoteDownlinkAudioLostRate}%`).fontColor($r('app.color.light_blue')).fontSize(14)
                }

                Row() {
                  Text('下行网络延时: ').fontSize(14)
                  Text(`${this.remoteUplinkAudioRtt} ms`).fontColor($r('app.color.light_blue')).fontSize(14)
                }

                Row() {
                  Text('上行丢包率: ').fontSize(14)
                  Text(`${this.remoteUplinkAudioLostRate}%`).fontColor($r('app.color.light_blue')).fontSize(14)
                }
              }
              .width('50%')
              .margin({ left: 24 })
              .alignItems(HorizontalAlign.Start)
            }

            Row() {
              Text('本地视频 Track 质量：').statisticsTitleStyle()
              Text('远端视频 Track 质量：').statisticsTitleStyle()
            }

            Row() {
              Column({ space: 4 }) {
                Row() {
                  Text('上行帧率: ').fontSize(14)
                  Text(`${this.localUplinkVideoFps} fps`).fontColor($r('app.color.light_blue')).fontSize(14)
                }

                Row() {
                  Text('上行码率: ').fontSize(14)
                  Text(`${Math.ceil(this.localUplinkVideoBitrate / 1024)} kbps`)
                    .fontColor($r('app.color.light_blue'))
                    .fontSize(14)
                }

                Row() {
                  Text('上行网络延时: ').fontSize(14)
                  Text(`${this.localUplinkVideoRtt} ms`).fontColor($r('app.color.light_blue')).fontSize(14)
                }

                Row() {
                  Text('上行丢包率: ').fontSize(14)
                  Text(`${this.localUplinkVideoLostRate}%`).fontColor($r('app.color.light_blue')).fontSize(14)
                }
              }
              .width('50%')
              .margin({ left: 24 })
              .alignItems(HorizontalAlign.Start)

              Column({ space: 4 }) {
                Row() {
                  Text('下行码率: ').fontSize(14)
                  Text(`${Math.ceil(this.remoteDownlinkVideoBitrate / 1024)} kbps`)
                    .fontColor($r('app.color.light_blue'))
                    .fontSize(14)
                }

                Row() {
                  Text('下行丢包率: ').fontSize(14)
                  Text(`${this.remoteDownlinkAudioLostRate}%`).fontColor($r('app.color.light_blue')).fontSize(14)
                }

                Row() {
                  Text('下行网络延时: ').fontSize(14)
                  Text(`${this.remoteUplinkAudioRtt} ms`).fontColor($r('app.color.light_blue')).fontSize(14)
                }

                Row() {
                  Text('上行丢包率: ').fontSize(14)
                  Text(`${this.remoteUplinkAudioLostRate}%`).fontColor($r('app.color.light_blue')).fontSize(14)
                }
              }
              .width('50%')
              .margin({ left: 24 })
              .alignItems(HorizontalAlign.Start)
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('50%')
        .padding(16)
        .backgroundColor($r('app.color.view_background'))
        .borderRadius(10)
        .scrollable(ScrollDirection.Vertical)

        Row() {
          Text($r('app.string.media_statistics_tips'))
            .textAlign(TextAlign.Start)
            .fontColor(Color.Black)
            .align(Alignment.Bottom)
            .fontSize(13)
            .padding(3)
        }
        .width('100%')
        .height('10%')
        .padding(5)
        .align(Alignment.Bottom)
      }
    }
    .title('通话质量统计')
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