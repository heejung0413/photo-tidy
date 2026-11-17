export interface Coordinate {
  latitude: number
  longitude: number
}

export interface TimelinePhoto {
  id: string
  /** 촬영 시각. 1970년부터의 밀리초. */
  takenAt: number
  coordinate: Coordinate | null
}

/** 한곳에 머물며 찍은 사진들. 사진은 1장 이상이고 촬영 시각순이다. */
export interface TimelineStop {
  photos: TimelinePhoto[]
  /** 위치가 있는 사진 좌표의 평균. 위치 있는 사진이 없으면 null. */
  center: Coordinate | null
}

/** 하루치 머문 곳. */
export interface TimelineDay {
  /** 그날의 달력 날짜. "2026-11-14". */
  day: string
  stops: TimelineStop[]
}
