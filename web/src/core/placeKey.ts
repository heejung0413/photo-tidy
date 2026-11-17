import type { Coordinate } from './types'

/** 좌표를 소수 셋째 자리(약 100m 칸)로 반올림한 글자. 받아 온 장소 이름의 저장 열쇠로 쓴다. */
export function placeKey(coordinate: Coordinate): string {
  return `${coordinate.latitude.toFixed(3)},${coordinate.longitude.toFixed(3)}`
}
