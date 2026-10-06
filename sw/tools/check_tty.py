"""Native production-C editor/parser checks plus a string-based edit oracle."""
import ctypes as C
from pathlib import Path
import random
import subprocess

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'build/ptrocos_shell';out.mkdir(parents=True,exist_ok=True)
subprocess.run(['gcc.exe','-std=c11','-O2','-Wall','-Wextra','-Werror','-shared',
                str(ROOT/'sw/ptrocos/tty.c'),str(ROOT/'sw/ptrocos/shell.c'),
                '-o',str(out/'tty.dll')],check=True)
lib=C.CDLL(str(out/'tty.dll'))
TEXT=C.CFUNCTYPE(None,C.c_void_p,C.c_char_p)
REDRAW=C.CFUNCTYPE(None,C.c_void_p,C.c_char_p,C.c_uint,C.c_uint)
CLEAR=C.CFUNCTYPE(None,C.c_void_p)
COMMAND=C.CFUNCTYPE(None,C.c_void_p,C.c_char_p)
class Callbacks(C.Structure):
    _fields_=[('text',TEXT),('redraw',REDRAW),('clear',CLEAR),('command',COMMAND),('context',C.c_void_p)]
class Tty(C.Structure):
    _fields_=[('callbacks',Callbacks),('line',C.c_char*64),('draft',C.c_char*64),('history',(C.c_char*64)*4)]+[
        (name,C.c_uint) for name in 'length cursor history_count history_next browse escape escape_number overflow last_cr'.split()]
lib.tty_init.argtypes=[C.POINTER(Tty),C.POINTER(Callbacks)]
lib.tty_key.argtypes=[C.POINTER(Tty),C.c_int]
lib.tty_uart_byte.argtypes=[C.POINTER(Tty),C.c_uint8]
lib.tty_uart_timeout.argtypes=[C.POINTER(Tty)]
lib.shell_parse.argtypes=[C.c_char_p,C.POINTER(C.c_char_p),C.POINTER(C.c_uint)]
lib.shell_u32.argtypes=[C.c_char_p,C.POINTER(C.c_uint32)]
lib.shell_complete.argtypes=[C.c_char_p];lib.shell_complete.restype=C.c_char_p
events=0

class Terminal:
    def __init__(self):
        self.commands=[];self.output=[];self.frames=[];self.clears=0
        self.sinks=(TEXT(lambda ctx,text:self.output.append(text.decode())),
                    REDRAW(lambda ctx,text,length,caret:self.frames.append((text.decode(),length,caret))),
                    CLEAR(lambda ctx:setattr(self,'clears',self.clears+1)),
                    COMMAND(lambda ctx,text:self.commands.append(text.decode())))
        self.callbacks=Callbacks(*self.sinks,None);self.state=Tty()
        lib.tty_init(C.byref(self.state),C.byref(self.callbacks))
    def feed(self,keys,uart=False):
        global events
        for key in keys:
            events+=1
            (lib.tty_uart_byte if uart else lib.tty_key)(C.byref(self.state),ord(key) if isinstance(key,str) else key)
        return self
    @property
    def line(self):return self.state.line.decode()

t=Terminal().feed('echo ac').feed([0x102]).feed('b').feed([10])
assert t.commands==['echo abc']
t.feed('echo qz').feed([0x104,0x103,0x103,0x103,0x103,0x103,0x106]).feed('xy').feed([0x105,8,10])
assert t.commands[-1]=='echo xy'
t.feed('draft').feed([0x100,0x100,0x101,0x101]);assert t.line=='draft'
t.feed([21]);t.feed('ec\tquoted\r\n',True);assert t.commands[-1]=='echo quoted'
before=len(t.commands);t.feed('\n',True);assert len(t.commands)==before
t.feed('cancel').feed([3]);assert t.line==''
t.feed('kept').feed([12]);assert t.line=='kept' and t.clears==1
t.feed([21]).feed('word tail').feed([23]);assert t.line=='word '
t.feed([1]).feed([11]);assert t.line==''
t.feed('x'*64).feed([10]);assert 'line too long; discarded\r\n' in t.output
assert not any(command.startswith('x'*30) for command in t.commands)
t.feed('prefix').feed([0x1ff]);assert t.line=='' and 'input lost; line discarded\r\n' in ''.join(t.output)
t.feed('abc\x1b[DZ\x1b[3~\x1b[H!\x1b[F\r',True);assert t.commands[-1]=='!abZ'
t.feed('x\x1b[9999999999Z',True);assert t.state.escape==0
t.feed([21]);t.feed('\x1b[',True);lib.tty_uart_timeout(C.byref(t.state));t.feed('echo timeout\r',True)
assert t.commands[-1]=='echo timeout'
left=Terminal().feed('echo left\n');right=Terminal().feed('echo right\n')
left.feed([0x100]);right.feed([0x100]);assert left.line=='echo left' and right.line=='echo right'
for i in range(7): left.feed([21]).feed(f'echo {i}\n')
left.feed([0x100]*10);assert left.line=='echo 3'

rng=random.Random(0x54545935)
f=Terminal();expected='';caret=0;overflow=False
for i in range(20000):
    key=rng.choice([rng.randrange(32,127),0x102,0x103,0x104,0x105,0x106,8,21,11,23,10])
    if 32<=key<127:
        if len(expected)<63:expected=expected[:caret]+chr(key)+expected[caret:];caret+=1
        else:overflow=True
    elif key==0x102:caret=max(0,caret-1)
    elif key==0x103:caret=min(len(expected),caret+1)
    elif key==0x104:caret=0
    elif key==0x105:caret=len(expected)
    elif key==0x106:expected=expected[:caret]+expected[caret+1:]
    elif key==8 and caret:expected=expected[:caret-1]+expected[caret:];caret-=1
    elif key==21:expected='';caret=0;overflow=False
    elif key==11:expected=expected[:caret]
    elif key==23:
        start=caret
        while start and expected[start-1]==' ':start-=1
        while start and expected[start-1]!=' ':start-=1
        expected=expected[:start]+expected[caret:];caret=start
    elif key==10:
        previous=len(f.commands)
        f.feed([key])
        assert f.commands[previous:]==([expected] if expected and not overflow else [])
        expected='';caret=0;overflow=False
        assert f.line=='' and f.state.cursor==0
        continue
    f.feed([key]);assert (f.line,f.state.cursor)==(expected,caret),(i,key,f.line,expected)

fixtures={
    '':[], '   \t ':[], 'echo hello world':['echo','hello','world'],
    'echo "a b" \'c d\' e\\ f':['echo','a b','c d','e f'],
    'echo "" \'\'':['echo','',''], 'ec"ho" abc\\\"':['echo','abc"'],
    'echo \'a\\b\'':['echo','a\\b'], 'echo "a\\\"b"':['echo','a"b'],
    'one two three four five six seven eight':['one','two','three','four','five','six','seven','eight'],
}
for source,expected_args in fixtures.items():
    buffer=C.create_string_buffer(source.encode());argv=(C.c_char_p*8)();argc=C.c_uint()
    assert lib.shell_parse(buffer,argv,C.byref(argc))==0,source
    assert [argv[i].decode() for i in range(argc.value)]==expected_args,source
for source,code in [('echo "unfinished',1),('echo unfinished\\',2),('1 2 3 4 5 6 7 8 9',3)]:
    buffer=C.create_string_buffer(source.encode());argv=(C.c_char_p*8)();argc=C.c_uint()
    assert lib.shell_parse(buffer,argv,C.byref(argc))==code
for source,expected_number in [('0',0),('0009',9),('4294967295',2**32-1)]:
    result=C.c_uint32();assert lib.shell_u32(source.encode(),C.byref(result))==1 and result.value==expected_number
for source in ['', '-1','+1',' 1','1 ','4294967296','999999999999999999','1x']:
    result=C.c_uint32(17);assert lib.shell_u32(source.encode(),C.byref(result))==0 and result.value==17
assert lib.shell_complete(b'ec')==b'echo' and lib.shell_complete(b'') is None and lib.shell_complete(b'zzz') is None
print(f'TTY/PARSER PASS editor_events={events} random_events=20000 history isolation bounds loss ANSI completion quotes numbers')
