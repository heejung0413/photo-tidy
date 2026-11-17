/** 지도 타일 주소(오픈스트리트맵). 화면 지도와 공유 이미지가 같이 쓴다. */
export const TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
export const TILE_ATTRIBUTION = '© OpenStreetMap'
export const TILE_MAX_ZOOM = 19

export function tileURL(x: number, y: number, z: number): string {
  return TILE_URL.replace('{z}', String(z)).replace('{x}', String(x)).replace('{y}', String(y))
}
