import { hilog } from '@kit.PerformanceAnalysisKit';

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
  QNComponentController
} from 'qnrtckit'

@Styles
function paddingStyle() {
  .width('100%')
  .height('100%')
  .aspectRatio(9.0 / 16)
  .borderRadius(5)
  .backgroundColor(Color.White)
}

@Entry
@Component
export struct CameraVideoExample {
  @Consume('pathStack') pathInfos: NavPathStack;
  private token: string = ""
  private client: QNRTCClient | null = null;
  private micTrack: QNMicrophoneAudioTrack | null = null;
  private localTracks: QNLocalTrack[] = [];
  private cameraTrack: QNCameraVideoTrack | null = null;
  private localRenderComponentCtrl: QNComponentController = new QNComponentController();
  private remoteRenderComponentCtrl: QNComponentController = new QNComponentController();
  @State localRendervisibility: Visibility = Visibility.Hidden;
  @State remoteRendervisibility: Visibility = Visibility.Hidden;

  private clientListener: QNClientEventListener = {
    OnConnectionStateChanged: (state: QNConnectionState, info: QNConnectionDisconnectedInfo) => {
      if (state == QNConnectionState.Connected) {
        // set local render
        this.cameraTrack!.Play(this.localRenderComponentCtrl);
        this.localRendervisibility = Visibility.Visible;
        // publish local tracks
        this.client!.Publish(this.localTracks, null);
      }
    },
    OnSubscribed: (userid: string, remoteAudioTrackList: QNRemoteAudioTrack[],
      remoteVideoTrackList: QNRemoteVideoTrack[]) => {
      if (remoteVideoTrackList.length) {
        let remoteVideoTrack: QNRemoteVideoTrack = remoteVideoTrackList[0]
        // set remote render
        remoteVideoTrack.Play(this.remoteRenderComponentCtrl);
        this.remoteRendervisibility = Visibility.Visible;
      }
    },
    OnUserJoined: (remoteUserId: string, userData: string) => {
      console.log("OnUserJoined: ", remoteUserId);
    },
    OnUserLeft: (remoteUserId: string) => {
      console.log("OnUserLeft: ", remoteUserId);
    },
    OnUserReconnecting: (remoteUserId: string) => {
      console.log("OnUserReconnecting: ", remoteUserId);
    },
    OnUserReconnected: (remoteUserId: string) => {
      console.log("OnUserReconnected: ", remoteUserId);
    },
    OnUserPublished: (remoteUserId: string, remoteTrackList: QNRemoteTrack[]) => {
      console.log("OnUserPublished: ", remoteUserId);
    },
    OnUserUnpublished: (remoteUserId: string, remoteTrackList: QNRemoteTrack[]) => {
      console.log("OnUserUnpublished: ", remoteUserId);
    }
  }

  aboutToAppear(): void {
    this.initRtcClient();
    this.join();
  }

  aboutToDisappear(): void {
    this.client!.Leave();
    QNRTC.DeInit();
  }

  initRtcClient(): void {
    // set log
    let logConfig = new QNLogConfig();
    logConfig.dir = getContext(this).filesDir;
    logConfig.logLevel = 2;
    QNRTC.SetLogConfig(logConfig);
    // init rtc
    let setting = new QNRTCSetting();
    let ret = QNRTC.Init(setting);
    // create rtc client
    this.client = QNRTC.CreateClient(new QNRTCClientConfig())
    this.client!.SetClientEventListener(this.clientListener);
    // create track
    this.micTrack = QNRTC.CreateMicrophoneAudioTrack(new QNMicrophoneAudioTrackConfig());
    let videoTrackConfig = new QNCameraVideoTrackConfig()
    let videoCaptureConfig = new QNVideoCaptureConfig()
    let videoEncodeConfig = new QNVideoEncoderConfig()
    videoTrackConfig.encoderConfig = videoEncodeConfig;
    videoTrackConfig.captureConfig = videoCaptureConfig;
    this.cameraTrack = QNRTC.CreateCameraVideoTrack(videoTrackConfig)
  }

  join(): void {
    // get token
    let styledString: MutableStyledString = new MutableStyledString(JSON.stringify(this.pathInfos.getParamByIndex(0)))
    styledString.removeString(0, 1);
    styledString.removeString(styledString.length - 1, 1);
    this.token = styledString.getString();
    // join room
    this.client!.Join(this.token);
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
              console.log("local surfaceid", this.localRenderComponentCtrl.getXComponentSurfaceId());
            }).paddingStyle().align(Alignment.Center).visibility(this.localRendervisibility)
          }
          .width('50%')
          .height('50%')
          .backgroundColor(Color.Grey)

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
              console.log("remote surfaceid: ", this.remoteRenderComponentCtrl.getXComponentSurfaceId());
            }).paddingStyle().align(Alignment.Center).visibility(this.remoteRendervisibility)
          }
          .width('50%')
          .height('50%')
          .backgroundColor(Color.Grey)
        }

        Row() {
          // todo
        }
        .width('100%')
        .height('30%')
        .padding(5)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.Grey)
        .borderRadius(5)

        Row() {
          Text("Tips: 本示例仅展示一对一场景下 SDK 内置摄像头采集视频 Track 和麦克风采集音频 Track 的发布和订阅")
            .textAlign(TextAlign.Start)
            .fontColor(Color.Black)
            .align(Alignment.Bottom)
            .fontSize(13)
            .padding(3)
        }
        .width('100%')
        .height('15%')
        .padding(5)
        .justifyContent(FlexAlign.End)
      }
    }
  }
}