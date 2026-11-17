/** 브라우저에 저장해 둔 값. 없거나 읽지 못하면 fallback. */
export function loadJSON(key: string, fallback: unknown): unknown {
  try {
    const raw = localStorage.getItem(key)
    return raw === null ? fallback : JSON.parse(raw)
  } catch {
    return fallback
  }
}

/** 저장에 실패해도(저장 공간 없음, 사생활 보호 모드) 앱은 계속 동작한다. */
export function saveJSON(key: string, value: unknown): void {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // 저장하지 못하면 이번 방문 동안만 기억한다.
  }
}

export const STORAGE_KEYS = {
  /** 받아 온 장소 이름. placeKey → 이름. */
  placeNames: 'photo-tidy.place-names',
  /** 직접 붙인 장소 이름. */
  customNames: 'photo-tidy.custom-place-names',
} as const
