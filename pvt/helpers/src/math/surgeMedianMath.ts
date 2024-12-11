export function findMedian(arr: number[]): number {
  const mid = Math.floor(arr.length / 2),
    nums = [...arr].sort((a, b) => a - b);
  return arr.length % 2 !== 0 ? nums[mid] : Math.floor((nums[mid - 1] + nums[mid]) / 2);
}
