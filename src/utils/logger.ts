import chalk from 'chalk';

export const log = {
  success: (msg: string) => console.log(chalk.green('  ✓ ') + msg),
  error: (msg: string) => console.error(chalk.red('  ✗ ') + msg),
  info: (msg: string) => console.log(chalk.blue('  ℹ ') + msg),
  warn: (msg: string) => console.log(chalk.yellow('  ⚠ ') + msg),
  dim: (msg: string) => console.log(chalk.dim('    ' + msg)),
};
