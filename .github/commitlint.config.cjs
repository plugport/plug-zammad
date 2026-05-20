module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'refactor', 'test',
      'build', 'ci', 'chore', 'perf', 'style',
    ]],
    'header-max-length': [2, 'always', 72],
  },
};
