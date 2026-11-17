/** 주소에서 이름으로 쓸 칸. 좁은 곳(동)부터 넓은 곳(시·군) 순서. */
const ADDRESS_KEYS = [
  'suburb',
  'quarter',
  'neighbourhood',
  'village',
  'town',
  'borough',
  'city_district',
  'city',
  'municipality',
  'county',
]

const text = (value: unknown): string | null => {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  return trimmed === '' ? null : trimmed
}

/** 이름 서비스(Nominatim)의 응답에서 장소 이름을 고른다. 쓸 이름이 없으면 null. */
export function pickPlaceName(json: unknown): string | null {
  if (typeof json !== 'object' || json === null) {
    return null
  }
  const { address, name } = json as Record<string, unknown>
  if (typeof address === 'object' && address !== null) {
    for (const key of ADDRESS_KEYS) {
      const found = text((address as Record<string, unknown>)[key])
      if (found) return found
    }
  }
  return text(name)
}
