import 'package:actual/common/model/cursor_pagination_model.dart';
import 'package:actual/common/model/model_with_id.dart';
import 'package:actual/common/model/pagination_params.dart';
import 'package:actual/common/repository/base_pagination_repository.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _PaginationInfo {
  final int fetchCount;
  final bool fetchMore;
  final bool forceRefetch;

  _PaginationInfo({
    this.fetchCount = 20,
    this.fetchMore = false,
    this.forceRefetch = false,
  });
}

class PaginationProvider<T extends IModelWithId,
        U extends IBasePaginationRepository<T>>
    extends StateNotifier<CursorPaginationBase> {
  final U repository;
  final paginationThrottle = Throttle(
    Duration(seconds: 3),
    initialValue: _PaginationInfo(),
    // checkEquality -true   함수 실행할때 넣어주는 값이 똑같으면 실행하지 않는다.
    checkEquality: false,
  );

  PaginationProvider({
    required this.repository,
  }) : super(CursorPaginationLoading()) {
    paginate();

    // state ==> initialValue 가 들어가고 그 다음부터는 setValue에서 집어넣은 것이 들어감
    paginationThrottle.values.listen(
      (state) {
        _throttledPagination(state);
      },
    );
  }

  Future<void> paginate({
    int fetchCount = 20,
// true - 추가로 데이터 더 가져옴
// false - 새로고침(현재 상태를 덮어 씌움)
    bool fetchMore = false,
// 강제로 다시 로딩하기
// true - CursorPaginationLoading(),
    bool forceRefetch = false,
  }) async {
    paginationThrottle.setValue(_PaginationInfo(
      fetchMore: fetchMore,
      fetchCount: fetchCount,
      forceRefetch: forceRefetch,
    ));
  }

  _throttledPagination(_PaginationInfo info) async {
    final fetchCount = info.fetchCount;
    final fetchMore = info.fetchMore;
    final forceRefetch = info.forceRefetch;
    try {
// 5가지 가능성
// State의 상태 (CursorPagination 의 클래스가 5개)
// [상태가]
// 1) CursorPagination - 정상적으로 데이터가 있는 상태
// 2) CursorPaginationLoading - 데이터가 로딩중인 상태(현재 캐시 없음)
// 3) CursorPaginationError - 에러가 있는 상태
// 4) CursorPaginationRefetching - 첫번째 페이지부터 다시 데이터를 가져올 때
// 5) CursorPaginationFetchMore - 추가 데이터를 paginate 해오라는 요청을 받았을 때

// 바로 반환하는 상황
// 1) hasMore = false(기존 상태에 이미 다음 데이터가 없다는 값을 들고 있다면) : 데이터가 있어야 hasMore를 알수 있음(hasMore는 서버에서 받기때문에)
// 2) 로딩중 - fetchMore: true
//    fetchMore가 아닐 때 - 새로고침의 의도가 있을수 있다
// state is CursorPagination -> 데이터를 가지고있는 상태(처음엔 CursorPaginationLoading 이걸로 생성자에 넣었기 때문에 )
// 1)
      if (state is CursorPagination && !forceRefetch) {
        final pState = state as CursorPagination;
        if (!pState.meta.hasMore) {
          return;
        }
      }

// 2)
      final isLoading = state is CursorPaginationLoading;
      final isRefetching = state is CursorPaginationRefetching;
      final isFetchingMore = state is CursorPaginationFetchingMore;

      if (fetchMore && (isLoading || isRefetching || isFetchingMore)) {
        return;
      }

// PaginationParams 생성
      PaginationParams paginationParams = PaginationParams(
        count: fetchCount,
      );

// fetchMore
// 데이터를 추가로 더 가져오는 상황
      if (fetchMore) {
        final pState = state as CursorPagination<T>;
        state = CursorPaginationFetchingMore(
          meta: pState.meta,
          data: pState.data,
        ); // 통신중이라는 상태로 바꾼것

        paginationParams = paginationParams.copyWith(
          after: pState.data.last.id,
        );
      } else {
// 데이터를 처음부터 가져오는 상황
// 기존 데이터를 보존한채로 Fetch (API 요청)를 진행
        if (state is CursorPagination && !forceRefetch) {
// 기존 데이터가 존재하는 상황이면서 새로고침을 안하는 상황
          final pState = state as CursorPagination<T>;
          state = CursorPaginationRefetching<T>(
            meta: pState.meta,
            data: pState.data,
          );

// 데이터를 유지할 필요 없는 상황
        } else {
          state = CursorPaginationLoading();
        }
      }

      final resp = await repository.paginate(
        paginationParams: paginationParams,
      );

      if (state is CursorPaginationFetchingMore) {
        final pState = state as CursorPaginationFetchingMore<T>;

// 기존 데이터에
// 새로운 데이터 추가
        state = resp.copyWith(
          data: [
            ...pState.data,
            ...resp.data,
          ],
        );
      } else {
// 맨처음 통신한 초기응답값임
        state = resp;
      }
    } catch (e) {
      state = CursorPaginationError(message: '데이터를 가져오지 못했습니다.');
    }
  }
}
