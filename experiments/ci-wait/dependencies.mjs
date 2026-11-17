// Virtual event times, not timings of a GitHub run. No API is contacted.
const names = ['artifact-1', 'artifact-2', 'artifact-3', 'artifact-4'];
const ready = [120, 180, 240, 301];
const producerEnd = 386, matrixEnd = 481;
console.log('strategy\tartifact\tready\tdetected\tdelay\twait API calls');
const polling = (period, jobsEvery) => t => {
  const ticks = Math.ceil(t / period);
  return [ticks * period, ticks + 1 + Math.ceil(ticks / jobsEvery)];
};
for (const [strategy, observe] of [
  ['poll-10s/jobs-10s', polling(10,1)],
  ['poll-30s/jobs-120s', polling(30,4)],
  ['needs-build-matrix', () => [matrixEnd,0]],
  ['needs-producer', () => [producerEnd,0]],
  ['needs-dedicated-upload-job', () => [Math.max(...ready),0]]
]) {
  ready.forEach((t,index) => {
    const [detected,calls] = observe(t);
    console.log([strategy,names[index],t,detected,detected-t,calls].join('\t'));
  });
}
