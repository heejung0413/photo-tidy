import { pickPlaceName } from '../core/pickPlaceName'
import type { Coordinate } from '../core/types'

const ENDPOINT = 'https://nominatim.openstreetmap.org/reverse'

/**
 * 좌표 → 장소 이름(오픈스트리트맵 Nominatim). 좌표가 그 서버로 전송된다.
 * 그곳에 붙일 이름이 없으면 null. 요청이 실패하면(인터넷 없음, 서비스가 막음) 오류를 던진다.
 */
export async function reverseGeocode(coordinate: Coordinate): Promise<string | null> {
  const query = new URLSearchParams({
    format: 'jsonv2',
    lat: String(coordinate.latitude),
    lon: String(coordinate.longitude),
    zoom: '16',
    addressdetails: '1',
    'accept-language': navigator.language || 'ko',
  })
  const response = await fetch(`${ENDPOINT}?${query}`, { headers: { Accept: 'application/json' } })
  if (!response.ok) {
    throw new Error(`장소 이름 요청 실패: ${response.status}`)
  }
  return pickPlaceName(await response.json())
}
