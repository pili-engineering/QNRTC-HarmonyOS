import { util } from '@kit.ArkTS';

function uint8ArrayToString(array: Uint8Array): string {
  let textDecoderOptions: util.TextDecoderOptions = {
    fatal: false,
    ignoreBOM: true
  }
  let decodeToStringOptions: util.DecodeToStringOptions = {
    stream: false
  }
  let textDecoder = util.TextDecoder.create('utf-8', textDecoderOptions);
  let retStr = textDecoder.decodeToString(array, decodeToStringOptions);
  return retStr;
}

export function parseToken(token: string): object {
  let base64Helper = new util.Base64Helper()
  let index: number = token.lastIndexOf(':')
  let result = base64Helper.decodeSync(token.substring(index + 1))
  return JSON.parse(uint8ArrayToString(result))
}