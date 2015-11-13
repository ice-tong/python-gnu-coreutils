import subprocess, shlex

class Term:
    def __call_tput(self, cmd):
        p = subprocess.Popen(shlex.split(cmd), stdout=subprocess.PIPE)
        res = b'' 
        while True:
            tmp = p.stdout.read(128)
            if not tmp: break
            res += tmp
        p.wait()
        res = int(res.decode('utf-8'))
        return res

    def lines(self):
        cmd = 'tput lines'
        return self.__call_tput(cmd)

    def cols(self):
        cmd = 'tput cols'
        return self.__call_tput(cmd)


class _Getch:
    """Gets a single character from standard input.  Does not echo to the
screen."""
    def __init__(self):
        try:
            self.impl = _GetchWindows()
        except ImportError:
            self.impl = _GetchUnix()

    def __call__(self): return self.impl()


class _GetchUnix:
    def __init__(self):
        import tty, sys

    def __call__(self):
        import sys, tty, termios
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(sys.stdin.fileno())
            ch = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        return ch


class _GetchWindows:
    def __init__(self):
        import msvcrt

    def __call__(self):
        import msvcrt
        return msvcrt.getch()


getch = _Getch()
