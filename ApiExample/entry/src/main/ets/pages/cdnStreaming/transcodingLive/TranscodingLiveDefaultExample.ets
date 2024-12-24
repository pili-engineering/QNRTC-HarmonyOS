import {
  QNLogConfig,
  QNRTC,
  QNRTCClient,
  QNRTCSetting,
  QNRTCClientConfig,
  QNClientEventListener,
  QNConnectionState,
  QNConnectionDisconnectedInfo,
  Type,
  QNRemoteAudioTrack,
  QNRemoteVideoTrack,
  QNRemoteTrack,
  QNCustomMessage,
  QNLiveStreamingListener,
  QNLiveStreamingErrorInfo,
  QNTranscodingLiveStreamingTrack,
  QNStretchMode,
  QNComponentController,
  QNMicrophoneAudioTrack,
  QNLocalTrack,
  QNPublishResultCallback,
  QNErrorCode,
  QNCameraEventListener,
  QNCameraVideoTrackConfig,
  QNCameraFacing,
  QNVideoCaptureConfig,
  QNVideoEncoderConfig,
  QNMicrophoneAudioTrackConfig,
  QNMicrophoneEventListener,
  QNCameraVideoTrack,
  QNDegradationPreference
} from '@qiniu/qnrtckit'

import { promptAction, SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions } from '@kit.ArkUI';
import { VideoViewRender } from '../../../common/VideoViewRender'
import { scanBarcode, scanCore } from "@kit.ScanKit";
import { wantAgent, WantAgent } from "@kit.AbilityKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { util } from "@kit.ArkTS";
import { Constants } from "../../../common/Constants";

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
  .aspectRatio(3.0 / 4.0)
  .borderRadius(5)
  .backgroundColor($r('app.color.view_background'))
}

@Component
export struct TranscodingLiveDefaultExample {
  @Consume('pathStack') pathInfos: NavPathStack;
  @State isMicrophoneRecording: boolean = false
  @State microphoneRecordText: string = "开启麦克风"
  private connectionState: QNConnectionState = QNConnectionState.Disconnected;
  private client: QNRTCClient | null = null;
  private micTrack: QNMicrophoneAudioTrack | null = null;
  private cameraTrack: QNCameraVideoTrack | null = null;
  private localTracks: QNLocalTrack[] = [];
  private token: string = ""
  private recordingStopped: boolean = false
  @State localVideoVisibility: Visibility = Visibility.Hidden
  private localComponentController: QNComponentController = new QNComponentController()
  private remoteVideoView: VideoViewRender = new VideoViewRender(1)
  @State remoteVisibility: Visibility = Visibility.Hidden
  private remoteAudioTrackId: string = ""
  private isStarted: boolean = false
  private willHide: boolean = false
  @State trackX: number = 0
  @State trackY: number = 0
  @State trackZ: number = 0
  @State trackWidth: number = 480
  @State trackHeight: number = 848
  @State trackStretchMode: QNStretchMode = QNStretchMode.StretchFill
  @State isSupportSei: boolean = false
  private stretchModeTitle: string[] =
    ['保持比例填满', '保持比例，完整显示', '缩放填满（可能变形）'];
  private stretchModeIndex: number = 0
  private stretchModeText: string = this.stretchModeTitle[this.stretchModeIndex]
  @State trackIndexes: number[] = [0]
  @State trackOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: '本地用户' }, { text: '远端用户' }] as SegmentButtonItemTuple,
    multiply: false,
    selectedBackgroundColor: Color.White,
    fontColor: Color.Black,
    selectedFontColor: Color.Black,
  })
  private trackStretchModeTitle: string[] =
    ['保持比例填满', '保持比例，完整显示', '缩放填满（可能变形）'];
  private trackStretchModeIndex: number = QNStretchMode.StretchFill
  private trackStretchModeText: string = this.stretchModeTitle[this.trackStretchModeIndex]
  @State supportSeiIndexes: number[] = [0]
  @State supportSeiOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: '不支持' }, { text: '支持' }] as SegmentButtonItemTuple,
    multiply: false,
    selectedBackgroundColor: Color.White,
    fontColor: Color.Black,
    selectedFontColor: Color.Black,
  })
  /**
   * 房间事件监听回调
   */
  private clientListener: QNClientEventListener = {
    OnConnectionStateChanged: (state: QNConnectionState, info: QNConnectionDisconnectedInfo) => {
      console.log("房间状态变化：" + state)
      this.connectionState = state
      if (state == QNConnectionState.Connected) {
        // publish track
        this.client!.Publish(this.localTracks, this.publishCallback)
      }
      if (info === undefined) {
        console.log("no info")
      } else {
        console.log("info reason = ", info.reason)
        console.log("info errorMessage = ", info.errorMessage)
        console.log("info errorCode = ", info.errorCode)
      }
    },

    OnSubscribed: (userid: string, remoteAudioTrackList: QNRemoteAudioTrack[],
      remoteVideoTrackList: QNRemoteVideoTrack[]) => {
      console.log("订阅远端用户：" + userid)
      for (let index: number = 0; index < remoteVideoTrackList.length; index++) {
        let remoteVideoTrack: QNRemoteVideoTrack = remoteVideoTrackList[index];
        let userId: string = remoteVideoTrack.GetUserID()
        this.remoteVideoView.updateState(userId, remoteVideoTrack, QNStretchMode.StretchFit)
        this.remoteVisibility = Visibility.Visible
      }
      for (let index: number = 0; index < remoteAudioTrackList.length; index++) {
        let remoteAudioTrack: QNRemoteAudioTrack = remoteAudioTrackList[index];
        let userId: string = remoteAudioTrack.GetUserID()
        if (userId == this.remoteVideoView.userId) {
          this.remoteAudioTrackId = remoteAudioTrack.GetTrackID()
        }
      }
    },

    OnUserJoined: (remoteUserId: string, userData: string) => {
      console.log("远端用户：" + remoteUserId + " 加入")
    },

    OnUserLeft: (remoteUserId: string) => {
      console.log("远端用户：" + remoteUserId + " 离开")
    },

    OnUserReconnecting: (remoteUserId: string) => {
      console.log("远端用户：" + remoteUserId + " 重连中")
    },

    OnUserReconnected: (remoteUserId: string) => {
      console.log("远端用户：" + remoteUserId + " 重连成功")
    },

    OnUserPublished: (remoteUserId: string, remoteTrackList: QNRemoteTrack[]) => {
      console.log("远端用户：" + remoteUserId + " 发布")
    },

    OnUserUnpublished: (remoteUserId: string, remoteTrackList: QNRemoteTrack[]) => {
      console.log("远端用户：" + remoteUserId + " 取消发布")
      for (let index: number = 0; index < remoteTrackList.length; index++) {
        let remoteTrack: QNRemoteTrack = remoteTrackList[index];
        if (remoteTrack.IsVideo()) {
          let remoteVideoTrack: QNRemoteVideoTrack = remoteTrackList[index] as QNRemoteVideoTrack
          let userId: string = remoteVideoTrack.GetUserID()
          if (this.remoteVideoView.userId == userId) {
            this.remoteVideoView.updateState("", remoteVideoTrack, QNStretchMode.StretchFit)
            this.remoteVisibility = Visibility.Hidden
            this.remoteAudioTrackId = ""
          }
        }
      }
    },

    OnMessageReceived: (message: QNCustomMessage) => {
      console.log("收到房间内用户：" + message.msgId + " 发送的消息：" + message.msgText)
    }
  }
  /**
   * 麦克风事件监听回调
   */
  private microphoneEventListener: QNMicrophoneEventListener = {
    OnError: (errorCode: number, message: string) => {
      if (errorCode == QNErrorCode.MicCaptureFailed) {
        this.recordingStopped = true
        this.micTrack?.StopRecording()
      }
    }
  }
  /**
   * 摄像头事件监听回调
   */
  private cameraEventListener: QNCameraEventListener = {
    OnCaptureStarted: (): void => {
      console.log('开始采集')
    },
    OnCaptureStopped: (): void => {
      console.log('停止采集')
    },
    OnFirstFrameCaptured: (): void => {
      console.log('已采集首帧视频')
    },
    OnError: (errorCode: number, message: string): void => {
      console.log('摄像头错误：' + errorCode + ', ' + message)
    }
  }
  /**
   * 发布回调
   */
  private publishCallback: QNPublishResultCallback =
    (onPublished: boolean, errorCode: number, errorMessage: string) => {
      if (onPublished) {
        if (this.micTrack != undefined) {
          this.isMicrophoneRecording = true
          this.microphoneRecordText = "关闭麦克风"
        }
        console.log("publish callback success")
      } else {
        console.error("publish callback failed: ", errorCode, errorMessage)
      }
    }
  /**
   * 转推任务监听回调
   */
  private liveStreamingListener: QNLiveStreamingListener = {
    OnStarted: (streamID: string) => {
      this.isStarted = true
      promptAction.showToast({
        message: '默认合流转推开始',
        duration: 2000
      });
    },
    OnStopped: (streamID: string) => {
      this.isStarted = false
      promptAction.showToast({
        message: '默认合流转推停止',
        duration: 2000
      });
    },
    OnTranscodingTracksUpdated: (streamID: string) => {
      promptAction.showToast({
        message: '默认合流转推更新',
        duration: 2000
      });
    },
    OnError: (streamID: string, info: QNLiveStreamingErrorInfo) => {
      promptAction.showToast({
        message: '默认合流转推发生错误! code: ' + info.code + " message:" + info.message,
        duration: 2000
      });
    }
  }

  aboutToAppear(): void {
    this.initRtcClient()
    this.join()
  }

  aboutToDisappear(): void {
    if (this.client && this.connectionState == QNConnectionState.Connected) {
      this.unpublish()
      // 离开房间
      this.client!.Leave();
    }
    // 反初始化 RTC 释放资源
    QNRTC.DeInit();
  }

  initRtcClient(): void {
    // 设置日志等级
    let logConfig: QNLogConfig = new QNLogConfig();
    logConfig.dir = getContext(this).filesDir;
    logConfig.logLevel = 2;
    QNRTC.SetLogConfig(logConfig);
    // 初始化 RTC
    let setting: QNRTCSetting = new QNRTCSetting()
    let ret: number = QNRTC.Init(setting)
    console.log("init rtc, ret ", ret)
    // 创建 client
    this.client = QNRTC.CreateClient(new QNRTCClientConfig()) as QNRTCClient;
    if (this.client == null) {
      console.log("create rtc client, ret null")
    } else {
      console.log("create rtc client")
    }
    // 设置 listener
    this.client!.SetClientEventListener(this.clientListener)
    this.client!.SetLiveStreamingListener(this.liveStreamingListener)
    // 创建麦克风 track
    this.micTrack = QNRTC.CreateMicrophoneAudioTrack(new QNMicrophoneAudioTrackConfig())
    if (this.micTrack == null) {
      console.log("create mic, ret null")
    } else {
      console.log("create mic")
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
    videoTrackConfig.encoderConfig = videoEncodeConfig;
    videoTrackConfig.captureConfig = videoCaptureConfig;
    this.cameraTrack = QNRTC.CreateCameraVideoTrack(videoTrackConfig)

    if (this.micTrack) {
      this.localTracks.push(this.micTrack);
    }

    if (this.cameraTrack) {
      this.localTracks.push(this.cameraTrack);
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
    styledString.removeString(0, 1);
    styledString.removeString(styledString.length - 1, 1);
    this.token = styledString.getString();
    // 加房
    this.client!.Join(this.token);
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
    };

    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
      backgroundTaskManager.startBackgroundRunning(getContext(this),
        backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, wantAgentObj).then(() => {
        console.info(`Succeeded in operationing startBackgroundRunning.`);
      }).catch((err: BusinessError) => {
        console.error(`Failed to operation startBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
      });
    });
  }

  /**
   * 停止后台长时任务
   */
  stopBackgroundAudioRecording() {
    backgroundTaskManager.stopBackgroundRunning(getContext(this)).then(() => {
      console.info(`Succeeded in operationing stopBackgroundRunning.`);
    }).catch((err: BusinessError) => {
      console.error(`Failed to operation stopBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
    });
  }

  publish(): void {
    if (this.connectionState != QNConnectionState.Connected) {
      return
    }
    if (this.localTracks.length < 0) {
      console.log("publish has no track")
      return
    }
    if (this.client) {
      let ret: number = this.client.Publish(this.localTracks, this.publishCallback)
    }
  }

  unpublish(): void {
    if (this.connectionState != QNConnectionState.Connected) {
      return
    }
    if (this.localTracks.length < 0) {
      console.log("unpublish has no track")
      return
    }
    if (this.client) {
      let ret: number = this.client.UnPublish(this.localTracks);
      if (this.micTrack != undefined && ret == QNErrorCode.OK) {
        this.isMicrophoneRecording = false
        this.microphoneRecordText = "打开麦克风"
      }
    }
  }

  build() {
    NavDestination() {
      Stack() {
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
                controller: this.localComponentController
              }).paddingStyle().align(Alignment.Center).visibility(this.localVideoVisibility)
            }
            .width('50%')
            .height('50%')
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
                controller: this.remoteVideoView.comController
              }).paddingStyle().align(Alignment.Center).visibility(this.remoteVisibility)
            }
            .width('50%')
            .height('50%')
            .margin('1')
            .renderViewStyle()
            .backgroundColor($r('app.color.view_background'))
          }
        }
      }

      Column() {
        List() {
          ListItem() {
            Row() {
              Text('合流布局设置：')
                .textAlign(TextAlign.Start)
                .fontColor(Color.Black)
                .align(Alignment.Bottom)
                .fontSize(14)
            }.padding(5)
          }

          ListItem() {
            Row() {
              Text('待添加到合流布局的角色：')
                .textAlign(TextAlign.Start)
                .fontColor(Color.Gray)
                .align(Alignment.Bottom)
                .fontSize(13)
                .padding(3)
            }.padding(8)
          }

          ListItem() {
            Row() {
              SegmentButton({
                options: this.trackOptions,
                selectedIndexes: $trackIndexes
              }).width('100%')
            }.padding(8)
          }

          ListItem() {
            Row() {
              Text('视频 Track 布局：')
                .textAlign(TextAlign.Start)
                .fontColor(Color.Gray)
                .align(Alignment.Bottom)
                .fontSize(13)
                .padding(3)
            }.padding(8)
          }

          ListItem() {
            Row() {
              Text('x')
                .width('10%').textAlign(TextAlign.Center).fontColor(Color.Gray).fontSize(13)
              TextInput({ text: this.trackX.toString() })
                .type(InputType.Number)
                .width('22%')
                .fontSize(13)
                .onChange((value: string) => {
                  this.trackX = Number(value)
                })
              Text('y')
                .width('11%')
                .margin({ left: 8 })
                .textAlign(TextAlign.Center)
                .fontColor(Color.Gray)
                .fontSize(13)
              TextInput({ text: this.trackY.toString() })
                .type(InputType.Number)
                .width('22%')
                .fontSize(13)
                .onChange((value: string) => {
                  this.trackY = Number(value)
                })
              Text('z')
                .width('11%').textAlign(TextAlign.Center).fontColor(Color.Gray).fontSize(13)
              TextInput({ text: this.trackZ.toString() })
                .type(InputType.Number)
                .width('22%')
                .fontSize(13)
                .onChange((value: string) => {
                  this.trackZ = Number(value)
                })
            }
            .padding(8)
          }

          ListItem() {
            Row() {
              Text('width')
                .width('16%').textAlign(TextAlign.Center).fontColor(Color.Gray).fontSize(13)
              TextInput({ text: this.trackWidth.toString() })
                .type(InputType.Number)
                .width('32%')
                .fontSize(13)
                .onChange((value: string) => {
                  this.trackWidth = Number(value)
                })
              Text('height')
                .width('16%')
                .margin({ left: 8 })
                .textAlign(TextAlign.Center)
                .fontColor(Color.Gray)
                .fontSize(13)
              TextInput({ text: this.trackHeight.toString() })
                .type(InputType.Number)
                .width('32%')
                .fontSize(13)
                .onChange((value: string) => {
                  this.trackHeight = Number(value)
                })
            }
            .padding(8)
          }

          ListItem() {
            Row() {
              Text('合流填充模式').align(Alignment.Start).width('35%').fontColor(Color.Gray).fontSize(13)
              Select([{ value: this.trackStretchModeTitle[0] },
                { value: this.trackStretchModeTitle[1] },
                { value: this.trackStretchModeTitle[2] }])
                .selected(this.trackStretchModeIndex)
                .value(this.trackStretchModeText)
                .font({ size: 13 })
                .onSelect((index: number, text?: string | undefined) => {
                  this.trackStretchModeIndex = index;
                  if (text) {
                    this.trackStretchModeText = text;
                  }
                })
                .width('65%')
            }
            .padding(8)
          }

          ListItem() {
            Row() {
              Text('是否支持添加 SEI').align(Alignment.Start).width('45%').fontColor(Color.Gray).fontSize(13)
              SegmentButton({
                options: this.supportSeiOptions,
                selectedIndexes: $supportSeiIndexes
              }).width('55%')
            }
            .padding(8)
          }

          ListItem() {
            Row() {
              Text('音频 Track 布局：')
                .textAlign(TextAlign.Start)
                .fontColor(Color.Gray)
                .align(Alignment.Bottom)
                .fontSize(13)
                .width('35%')
              Text('无特殊配置参数，参考代码实现')
                .textAlign(TextAlign.Start)
                .fontColor(Color.Grey)
                .align(Alignment.Bottom)
                .fontSize(12)
                .width('65%')
            }.padding(8)
          }

          ListItem() {
            Row() {
              Button('添加合流布局')
                .onClick(() => {
                  if (this.trackIndexes[0] == 1 && this.remoteVideoView.trackId == "") {
                    promptAction.showToast({
                      message: '还未有远端用户加入',
                      duration: 2000
                    });
                    return
                  }

                  let currentVideoTrack: QNTranscodingLiveStreamingTrack = new QNTranscodingLiveStreamingTrack()
                  if (this.trackIndexes[0] == 0) {
                    currentVideoTrack.trackId = this.cameraTrack!.GetTrackID()
                  } else {
                    currentVideoTrack.trackId = this.remoteVideoView.trackId
                  }
                  currentVideoTrack.x = this.trackX
                  currentVideoTrack.y = this.trackY
                  currentVideoTrack.z = this.trackZ
                  currentVideoTrack.width = this.trackWidth
                  currentVideoTrack.height = this.trackHeight
                  currentVideoTrack.stretchMode = this.trackStretchMode
                  if (this.supportSeiIndexes[0] == 0) {
                    this.isSupportSei = false
                  } else {
                    this.isSupportSei = true
                  }
                  currentVideoTrack.isSupportSei = this.isSupportSei
                  let currentAudioTrack: QNTranscodingLiveStreamingTrack = new QNTranscodingLiveStreamingTrack()
                  if (this.trackIndexes[0] == 0) {
                    currentAudioTrack.trackId = this.micTrack!.GetTrackID()
                  } else {
                    currentAudioTrack.trackId = this.remoteAudioTrackId
                  }
                  // 默认合流无需设置流 ID
                  this.client?.AddTranscodingLiveStreamingTracks(null, [currentVideoTrack, currentAudioTrack])
                }).margin(8).width('40%')
              Button('移除合流布局')
                .onClick(() => {
                  if (this.trackIndexes[0] == 1 && this.remoteVideoView.trackId == "") {
                    promptAction.showToast({
                      message: '还未有远端用户加入',
                      duration: 2000
                    });
                    return
                  }
                  let currentVideoTrack: QNTranscodingLiveStreamingTrack = new QNTranscodingLiveStreamingTrack()
                  if (this.trackIndexes[0] == 0) {
                    currentVideoTrack.trackId = this.cameraTrack!.GetTrackID()
                  } else {
                    currentVideoTrack.trackId = this.remoteVideoView.trackId
                  }
                  let currentAudioTrack: QNTranscodingLiveStreamingTrack = new QNTranscodingLiveStreamingTrack()
                  if (this.trackIndexes[0] == 0) {
                    currentAudioTrack.trackId = this.micTrack!.GetTrackID()
                  } else {
                    currentAudioTrack.trackId = this.remoteAudioTrackId
                  }
                  // 默认合流无需设置流 ID
                  this.client?.RemoveTranscodingLiveStreamingTracks(null, [currentVideoTrack, currentAudioTrack])
                }).margin(8).width('40%')
            }.padding(8)
          }
        }
        .margin({ top: 16 })
      }
      .width('100%')
      .height('46%')
      .padding(10)
      .margin({ top: 10 })
      .justifyContent(FlexAlign.Start)
      .backgroundColor($r('app.color.view_background'))
      .borderRadius(10)

      Row() {
        Text("Tips：\n1. 本示例仅展示一对一场景下使用默认合流配置创建合流任务的功能。\n2. 使用转推功能需要在七牛后台开启对应 AppId 的转推功能开关。\n3. 默认合流任务使用七牛控制台下该 AppId 的合流配置，无需客户端创建。\n4. 添加布局即可触发合流转推，可以到 AppId 绑定的直播空间下查看活跃流。")
          .textAlign(TextAlign.Start)
          .fontColor(Color.Grey)
          .align(Alignment.Bottom)
          .fontSize(12)
          .padding(3)
      }
      .width('100%')
      .height('14%')
      .padding(5)
      .justifyContent(FlexAlign.End)
    }
    .title('默认合流转推')
    .onShown(() => {
      console.info('onShown')
      this.cameraTrack?.StartCapture()
      // 设置渲染视图
      if (this.localVideoVisibility != Visibility.Visible) {
        this.cameraTrack?.Play(this.localComponentController, QNStretchMode.StretchFit);
        this.localVideoVisibility = Visibility.Visible;
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