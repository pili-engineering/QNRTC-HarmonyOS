import { QNComponentController, QNRemoteVideoTrack, QNStretchMode } from "@qiniu/qnrtckit";

export class VideoViewRender {
  public comController: QNComponentController = new QNComponentController()
  public userId: string = ''
  public trackId: string = ''
  public index: number = 0
  public track: QNRemoteVideoTrack | null = null

  constructor(index: number) {
    this.index = index
  }

  public updateState(userId: string, track: QNRemoteVideoTrack, mode: QNStretchMode) {
    if (userId == "") {
      this.track = null
      this.userId = ""
      this.trackId = ""
      track.Play(null, mode)
    } else {
      this.track = track
      this.userId = track.GetUserID()
      this.trackId = track.GetTrackID()
      track.Play(this.comController, mode)
    }
  }
}