import { scanCore, scanBarcode } from '@kit.ScanKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CameraVideoExample } from './video/cameraVideo/CameraVideoExample';
import { abilityAccessCtrl, common, Permissions, UIAbility } from '@kit.AbilityKit';
import prompt from '@ohos.prompt'

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
  titleBackgroundColor: ResourceColor = '#fff0f0f0'
  egDivider: DividerList = new DividerList(1, 10, 10, '#ffd0d0d0')
  private pushClicked : boolean = false;
  token: string = ""

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
      .backgroundColor(this.titleBackgroundColor)
      .width('100%')
      .height(40)
      .padding(5)
  }

  @Builder
  ListItemFunc(title: string, pathName: string) {
    ListItem() {
      Row() {
        Column() {
          Text(title).fontSize(this.itemTitleSize).alignSelf(ItemAlign.Start).width('100%').height('100%')
        }.width('100%').height(40)
      }
    }.padding(5)
    .onClick(() => {
      if (this.pushClicked){
        return;
      }
      if (this.token) {
        this.pushClicked = true;
        this.pathStack.pushPathByName(pathName, this.token);
      } else {
        prompt.showToast({
          message: 'Token 为空，请点击扫描获取 Token',
          duration: 2000
        });
      }
    })
  }

  @Builder
  PageMap(name: string) {
    NavDestination() {
      if (name == "CameraVideoExample") {
        CameraVideoExample()
      }
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
                prompt.showToast({
                  message: '获取Token成功，请点击进入相关页面',
                  duration: 2000
                });
              } else {
                prompt.showToast({
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
          this.ListItemFunc('摄像头采集音视频通话',
            'CameraVideoExample')
        }.margin({ bottom: 5 }).divider(this.egDivider)
      }
      .sticky(StickyStyle.Header)
      .scrollBar(BarState.Auto)
      .height('95%')
    }
    .navDestination(this.PageMap)
    .hideTitleBar(false)
    .title("ApiExample")
    .menus(this.NavigationMenus)
  }
}