export const Tuning = {
  /** 머문 곳 중심에서 이 거리(미터) 이내면 같은 곳으로 본다. */
  stopRadius: 200,
  /** 장소 이름 요청을 시작하는 최소 간격(밀리초). 이름 서비스가 1초에 1번만 허용한다. */
  placeNameInterval: 1100,
  /** 공유 이미지에 담는 머문 곳 수. */
  shareMaxStops: 40,
  /** 공유 이미지에서 머문 곳마다 그리는 썸네일 수. */
  shareThumbnails: 4,
} as const
