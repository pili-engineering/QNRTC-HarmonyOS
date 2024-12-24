import { scanCore, scanBarcode } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CameraVideoExample } from './video/cameraVideo/CameraVideoExample';
import { TranscodingLiveDefaultExample } from './cdnStreaming/transcodingLive/TranscodingLiveDefaultExample';
import { TranscodingLiveCustomExample } from './cdnStreaming/transcodingLive/TranscodingLiveCustomExample';
import { abilityAccessCtrl, common, Permissions, UIAbility } from '@kit.AbilityKit';
import { DirectLiveStreamingExample } from './cdnStreaming/directLive/DirectLiveStreamingExample';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { parseToken } from '../common/Utils';
import { QNRTC } from '@qiniu/qnrtckit';
import { MediaStatisticsExample } from './others/MediaStatisticsExample';
import { ScreenSharingExample } from './video/screenSharing/ScreenSharingExample'

class DividerList {
  strokeWidth: Length
  startMargin: Length
  endMargin: Length
  color: ResourceColor

  constructor(strokeWidth: Length, startMargin: Length, endMargin: Length, color: ResourceColor) {
    this.strokeWidth = strokeWidth
    this.startMargin = startMargin
    this.endMargin = endMargin
    this.color = color
  }
}

const permissions: Array<Permissions> =
  ['ohos.permission.MICROPHONE', 'ohos.permission.CAMERA', 'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY',
    'ohos.permission.INTERNET'];

function reqPermissionsFromUser(permissions: Array<Permissions>, context: common.UIAbilityContext): void {
  let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  // requestPermissionsFromUser会判断权限的授权状态来决定是否唤起弹窗
  atManager.requestPermissionsFromUser(context, permissions).then((data) => {
    let grantStatus: Array<number> = data.authResults;
    let length: number = grantStatus.length;
    for (let i = 0; i < length; i++) {
      if (grantStatus[i] === 0) {
        // 用户授权，可以继续访问目标操作
      } else {
        // 用户拒绝授权，提示用户必须授权才能访问当前页面的功能，并引导用户到系统设置中打开相应的权限
        return;
      }
    }
    // 授权成功
  }).catch((err: BusinessError) => {
    console.error(`Failed to request permissions from user. Code is ${err.code}, message is ${err.message}`);
  })
}

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  itemTitleSize: number = 15
  egDivider: DividerList = new DividerList(1, 10, 10, '#ffd0d0d0')
  private pushClicked: boolean = false;
  token: string = ""
  @State roomInfoVisibility: Visibility = Visibility.None
  @State appID: string = ''
  @State userID: string = ''
  @State roomName: string = ''

  aboutToAppear(): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    reqPermissionsFromUser(permissions, context);
    this.pathStack.setInterception({
      didShow: (from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        operation: NavigationOperation, animated: boolean) => {
        if (operation == NavigationOperation.POP) {
          this.pushClicked = false;
        }
      }
    })
  }

  @Builder
  GroupHead(text: string) {
    Text(text)
      .fontSize(this.itemTitleSize)
      .backgroundColor($r('app.color.title_background'))
      .width('100%')
      .height(40)
      .padding({ left: 16 })
  }

  @Builder
  ListItemFunc(title: string, pathName: string) {
    ListItem() {
      Row() {
        Column() {
          Text(title).fontSize(this.itemTitleSize).alignSelf(ItemAlign.Start).width('100%').height('100%')
        }.width('100%').height(40)
      }
    }.padding({ left: 16 })
    .onClick(() => {
      if (this.pushClicked) {
        return;
      }
      if (this.token) {
        this.pushClicked = true;
        this.pathStack.pushPathByName(pathName, this.token);
      } else {
        promptAction.showToast({
          message: 'Token 为空，请点击扫描获取 Token',
          duration: 2000
        });
      }
    })
  }

  @Builder
  PageMap(name: string) {
    if (name == "CameraVideoExample") {
      CameraVideoExample()
    } else if (name == 'DirectLiveStreamingExample') {
      DirectLiveStreamingExample()
    } else if (name == 'MediaStatisticsExample') {
      MediaStatisticsExample()
    } else if (name == "TranscodingLiveDefaultExample") {
      TranscodingLiveDefaultExample()
    } else if (name == "TranscodingLiveCustomExample") {
      TranscodingLiveCustomExample({roomName: this.roomName})
    } else if (name == "ScreenSharingExample") {
      ScreenSharingExample()
    }
  }

  @Builder
  NavigationMenus() {
    Row() {
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
          };
          try {
            // 可调用getContext接口获取当前页面关联的UIAbilityContext
            scanBarcode.startScanForResult(getContext(this), options).then((result: scanBarcode.ScanResult) => {
              // 解析码值结果跳转应用服务页
              console.info(`Succeeded in getting ScanResult by promise with options, result is ${result.originalValue}`);
              if (result.originalValue) {
                this.token = result.originalValue
                let roomInfo: object = parseToken(this.token)
                this.appID = roomInfo?.['appId']
                this.userID = roomInfo?.['userId']
                this.roomName = roomInfo?.['roomName']
                this.roomInfoVisibility = Visibility.Visible
                promptAction.showToast({
                  message: '获取Token成功，请点击进入相关页面',
                  duration: 2000
                });
              } else {
                promptAction.showToast({
                  message: '获取Token失败',
                  duration: 2000
                });
              }
            }).catch((error: BusinessError) => {
              console.error(`Failed to get ScanResult by promise with options. Code:${error.code}, message: ${error.message}`);
            });
          } catch (error) {
            console.error(`Failed to start the scanning service. Code:${error.code}, message: ${error.message}`);
          }
        })
    }
  }

  build() {
    Navigation(this.pathStack) {
      List() {
        ListItemGroup({ header: this.GroupHead('视频通话相关') }) {
          this.ListItemFunc('摄像头采集音视频通话', 'CameraVideoExample')
          this.ListItemFunc('屏幕共享音视频通话', 'ScreenSharingExample')
        }.margin({ bottom: 5 }).divider(this.egDivider)

        ListItemGroup({ header: this.GroupHead('CDN 直播相关') }) {
          this.ListItemFunc('CDN 单人转推', 'DirectLiveStreamingExample')
          this.ListItemFunc('CDN 合流转推（默认合流任务）',
            'TranscodingLiveDefaultExample')
          this.ListItemFunc('CDN 合流转推（自定义合流任务）',
            'TranscodingLiveCustomExample')
        }.margin({ bottom: 5 }).divider(this.egDivider)

        ListItemGroup({ header: this.GroupHead('其他功能') }) {
          this.ListItemFunc('通话质量统计', 'MediaStatisticsExample')
        }.margin({ bottom: 5 }).divider(this.egDivider)
      }
      .sticky(StickyStyle.Header)
      .scrollBar(BarState.Auto)
      .height('85%')
      .backgroundColor(Color.White)

      Column() {
        Text(`appID: ${this.appID}`).fontSize(12).width('100%')
        Text(`用户名: ${this.userID}`).fontSize(12).width('100%')
        Text(`房间号: ${this.roomName}`).fontSize(12).width('100%')
        Text(`SDK 版本号: ${QNRTC.GetVersion()}`).fontSize(12).width('100%')
      }
      .width('100%')
      .height('15%')
      .padding({ left: 24 })
      .justifyContent(FlexAlign.SpaceEvenly)
      .visibility(this.roomInfoVisibility)
      .backgroundColor($r('app.color.title_background'))
    }
    .navDestination(this.PageMap)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleMode(NavigationTitleMode.Mini)
    .title("ApiExample")
    .backgroundColor($r('app.color.title_background'))
    .menus(this.NavigationMenus)
  }
}