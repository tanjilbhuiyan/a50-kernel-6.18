/* SPDX-License-Identifier: Apache-2.0 */
#include <stdio.h>
#include <unistd.h>

#include "sw_sync.h"
#include "sync.h"

static int check_merge(int fence, int expected_signaled)
{
	int signaled = sync_fence_count_with_status(fence, FENCE_STATUS_SIGNALED);
	int active = sync_fence_count_with_status(fence, FENCE_STATUS_ACTIVE);
	int ready = sync_wait(fence, 0);
	printf("merged fence: signaled=%d active=%d poll=%d\n", signaled, active, ready);
	return signaled == expected_signaled && active == 2 - expected_signaled &&
	       ready == (expected_signaled == 2);
}

int main(void)
{
	int timeline_a = sw_sync_timeline_create();
	if (timeline_a < 0) {
		perror("open sw_sync timeline A");
		return 1;
	}
	int timeline_b = sw_sync_timeline_create();
	if (timeline_b < 0) {
		perror("open sw_sync timeline B");
		return 1;
	}
	int fence_a = sw_sync_fence_create(timeline_a, "a50-sync-a", 1);
	if (fence_a < 0) {
		perror("create sw_sync fence A");
		return 1;
	}
	int fence_b = sw_sync_fence_create(timeline_b, "a50-sync-b", 1);
	if (fence_b < 0) {
		perror("create sw_sync fence B");
		return 1;
	}
	int merged = sync_merge("a50-merge", fence_a, fence_b);
	if (merged < 0) {
		perror("SYNC_IOC_MERGE");
		return 1;
	}
	if (!check_merge(merged, 0))
		return 1;
	if (sw_sync_timeline_inc(timeline_a, 1) < 0) {
		perror("increment sw_sync timeline A");
		return 1;
	}
	if (!check_merge(merged, 1))
		return 1;
	if (sw_sync_timeline_inc(timeline_b, 1) < 0) {
		perror("increment sw_sync timeline B");
		return 1;
	}
	if (!check_merge(merged, 2))
		return 1;

	close(merged);
	sw_sync_fence_destroy(fence_b);
	sw_sync_fence_destroy(fence_a);
	sw_sync_timeline_destroy(timeline_b);
	sw_sync_timeline_destroy(timeline_a);
	puts("PASS: software timeline fences merge and signal in order");
	return 0;
}
