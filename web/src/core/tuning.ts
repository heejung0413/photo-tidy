export const Tuning = {
  /** 머문 곳 중심에서 이 거리(미터) 이내면 같은 곳으로 본다. */
  stopRadius: 200,
  /** 장소 이름 요청을 시작하는 최소 간격(밀리초). 이름 서비스가 1초에 1번만 허용한다. */
  placeNameInterval: 1100,
  /** 이름을 받지 못한 머문 곳이 남았을 때 다시 물어보기까지 기다리는 시간(밀리초). 연달아 실패한 뒤 쉬는 1분보다 길다. */
  placeNameRetryDelay: 65_000,
  /** 공유 이미지에 담는 머문 곳 수. */
  shareMaxStops: 40,
  /** 공유 이미지에서 머문 곳마다 그리는 썸네일 수. */
  shareThumbnails: 4,
} as const
