( This program is written in a pseudo Forth like language,
it is not Forth and does not behave like it, it just looks
like it. This should be thought of as assembly code and
not Forth.

A lot of the code has been taken verbatim from "The Zen
of eForth by C. H. Ting".

For a grammar of the language look into the file "h2.c".

Execution begins at a label called "start".

TODO:
* Function for displaying numbers on the display
* VGA driver
* Hex number printer
* Bootloader
* Minimal Forth interpreter 
* Add built in words to the dictionary
* Turn this into a literal file
* Add assembler directives for setting starting position of
program counter and the like )

( ======================== System Constants ================= )

.mode 1 ( Turn word header compilation on )


( Outputs: 0x6000 - 0x7FFF )
constant oUart         0x6000
constant oLeds         0x6001
constant oTimerCtrl    0x6002
constant oVgaCursor    0x6003
constant oVgaCtrl      0x6004
constant o8SegLED      0x6005
constant oIrcMask      0x6006

( Inputs: 0x6000 - 0x7FFF )
constant iUart         0x6000
constant iSwitches     0x6001
constant iTimerCtrl    0x6002
constant iTimerDin     0x6003
constant iVgaTxtDout   0x6004
constant iPs2          0x6005

( Interrupt service Routine: Memory locations )
constant isrNone           0
constant isrRxFifoNotEmpty 1
constant isrRxFifoFull     2
constant isrTxFifoNotEmpty 3
constant isrTxFifoFull     4
constant isrKbdNew         5
constant isrTimer          6
constant isrBrnLeft        7


: isrNoop >r drop ; ( Return to suspended instruction )

\ .isr reset isrBtnRight
.isr isrNoop isrRxFifoNotEmpty
.isr isrNoop isrRxFifoFull
.isr isrNoop isrTxFifoNotEmpty
.isr isrNoop isrTxFifoFull
.isr isrNoop isrKbdNew
.isr isrNoop isrTimer
.isr isrNoop isrBrnLeft

( ======================== System Constants ================= )

( ======================== System Variables ================= )


variable pwd 0 ( Present Word Variable: Set at end of file )
variable cp  0 ( Dictionary Pointer: Set at end of file )

( ======================== System Variables ================= )

( ======================== Forth Kernel ===================== )


: ! store drop ;
: 256* 8 lshift ;
: 256/ 8 rshift ;
: sp@ depth ;
: 1+ 1 + ;
: 2+ 2 + ;
: 2/ 1 rshift ;
: 2* 1 lshift ;
: >= < invert ;
: >  swap < ;
: u> swap u< ;
: u>= u< invert ;
: <> = invert ;
: 0<> 0= invert ;
: 0>  0 > ;
: 0<  0 < ;
: 2dup over over ;
: 2drop drop drop ;
: tuck swap over ;
: negate invert 1+ ;
: - negate + ;
: 2- 2 - ;
: +! tuck @ + swap ! ;
: 1+! 1 swap +! ;
: ?dup dup if dup then ;
: execute >r ;
: c@ dup @ swap 1 and if 256/ else 0xff and then ;
: c! 
	swap 0xff and dup 256* or swap
	tuck dup @ swap 1 and 0 = 0xff xor
	>r over xor r> and xor swap ! ;

: !io ; ( Initialize I/O devices )
: ?rx ( -- c 1 | 0 : read in a character of input from UART )
	iUart @ 0x0100 and if 0xff and 1 else drop 0 then ;
: tx! ( c -- : write a character to UART )
	0x2000 or oUart ! ; ( @todo loop until TX FIFO is not full )

: um+ ( w w -- w carry )
	2dup + >r
	r@ 0 >= >r
	2dup and
	0< r> or >r
	or 0< r> and negate
	r> swap ;

( ======================== Forth Kernel ===================== )

( ======================== Word Set ========================= )

( With the built in words defined in the assembler, and the words
defined so far, all of the primitive words needed by eForth should
be available. )

: cell- 2- ;
: cell+ 2+ ;
: cells 2* ;
: 2! ( d a -- ) tuck ! cell+ ! ;
: 2@ ( a -- d ) dup cell+ @ swap @ ;
: here cp @ ;
: pad here 80 + ;
: @execute @ ?dup if execute then ;
: bl 32 ;
: within over - >r - r> u< ; ( u lo hi -- t )
: not -1 xor ;
: dnegate not >r not 1 um+ r> + ; ( d -- d )
: abs dup 0< if negate then ;
: count ( cs -- c-addr u )
	dup 1+ swap c@ ;
	\ dup c@ swap 1+ swap ;
: rot >r swap r> swap ;
: -rot swap >r swap r> ;
: min  2dup < if drop else nip then ;
: max  2dup > if drop else nip then ;
: >char ( c -- c : convert character to '_' if not ASCII or is control char )
  0x7f and dup 127 bl within if drop [char] _ then ;

: um/mod ( ud u -- ur uq )
	2dup u<
	if negate  15
		for >r dup um+ >r >r dup um+ r> + dup
			r> r@ swap >r um+ r> or
			if >r drop 1 + r> else drop then r>
		next 
		drop swap exit
	then drop 2drop  -1 dup ;

: m/mod ( d n -- r q ) \ floored division
	dup 0< dup >r
	if 
		negate >r dnegate r>
	then 
	>r dup 0< if r@ + then r> um/mod r>
	if swap negate swap then ;

: /mod ( n n -- r q ) over 0< swap m/mod ;
: mod ( n n -- r ) /mod drop ;
: / ( n n -- q ) /mod swap drop ;

: um* ( u u -- ud )
	0 swap ( u1 0 u2 ) 15
	for dup um+ >r >r dup um+ r> + r>
		if >r over um+ r> + then
	next rot drop ;

: * ( n n -- n ) um* drop ;

: m* ( n n -- d )
	2dup xor 0< >r abs swap abs um*  r> if dnegate then ;

: */mod ( n n n -- r q ) >r m* r> m/mod ;
: */ ( n n n -- q ) */mod swap drop ;

: aligned ( b -- a )
	dup 0 2 um/mod drop dup
	if 2 swap - then + ;

( ======================== Word Set ========================= )

( ======================== System setup ===================== )

( Initial value of VGA
  BIT     MEANING
  7   -  Display Next Screen
  6   -  Enable VGA
  5   -  Cursor enable
  4   -  Cursor blinks
  3   -  Cursor mode
  2   -  Red
  1   -  Green
  0   -  Blue )
constant vgaInit       0x7A \ 0x007A

constant vgaX          80
constant vgaY          40
constant vgaTextSize   3200

( Initial value of timer
  BIT     MEANING
  15   -  Enable Timer
  14   -  Reset Timer Value immediately
  13   -  Interrupt Enable
  12-0 -  Value to compare against )
constant timerInit     0x8032

variable cursorX 0  ( x component of cursor )
variable cursorY 0  ( y component of cursor )
variable cursorT 0  ( index into VGA text memory )



( If the VGA display was 64 characters by 16 lines of text 
this cursor logic would be a lot simpler )
: y1+ cursorY 1+! cursorY @ vgaY u>= if 0 cursorY ! then ;
: x1+ cursorX 1+! cursorX @ vgaX u>= if 0 cursorX ! y1+ then ;
: cursorT1+ cursorT 1+! cursorT @ vgaTextSize u>= if 0 cursorT ! then ;

: led ( n -- : display a number on the LED 8 display )
	o8SegLED ! ;

: uart-write ( char -- bool : write out a character )
	0x2000 or oUart ! 1 ; \ @todo Check that the write succeeded by looking at the TX FIFO

: key?
	iUart @ 0x0100 and ;

variable uart-read-count 0

: uart-read  ( -- char : blocks until character read in )
	begin key? 0= until 0x0400 oUart ! iUart @ 0xff and
	uart-read-count 1+!
	uart-read-count @ led ;

: emit ( char -- : write out a char )
	uart-write drop ;

: key ( -- char : read in a key, echoing to output )
	uart-read dup emit ;

: char
	uart-read ;

: cr 10 emit ;
: space bl emit ;

constant bootstart 1024
constant programsz 5120 ( bootstart + 4096 )
variable readin    0

: boot
	bootstart readin !
	begin
		key 8 lshift ( big endian )
		key
		or readin !
		readin 1+!
		readin @ programsz u>=
	until
	r> drop
	branch bootstart ;

\ @todo This should also set the address of oVgaTxtAddr to
\ "x * y", however this would require multiplication to
\ to be implemented.
: at-xy ( x y -- : set terminal cursor to x-y position )
	256* or oVgaCursor ! ;

: init
	vgaInit   oVgaCtrl   ! \ Turn on VGA monitor
	timerInit oTimerCtrl ! \ Enable timer
	0xCAFE led ;
	\ 0x00FF oIrcMask !
	\ 1   seti ;

( The start up code begins here, on initialization the assembler
jumps to a special symbol "start".

@todo This special case symbol should be removed by adding
adequate assembler directives )

variable welcome "H2 Forth:"

: /string ( c-addr u1 u2 -- c-addr u : advance a string u2 characters )
	over min rot over + -rot - ;

: type
 	dup 0= if 2drop exit then
 	begin 
 		swap dup c@ emit 1+ swap 1-
 		dup 0=
 	until 2drop ;

: latest pwd @ ;

: words
	latest
	begin
		dup
	while
		dup cell+ count type space @
	repeat drop cr ;

( ======================== System setup ===================== )

( ======================== Starting Code ==================== )

start:
	 init

	\ boot

	welcome count type cr  
	words

nextChar:

	begin
		iSwitches @ 0xff and oLeds !  \ Set LEDs to switches
		key? 0=                \ Wait for UART character
	until
	key cursorT @ 0xE000 or !

	x1+
	cursorT1+

	cursorX @ cursorY @ at-xy

branch nextChar

( ======================== User Code ======================== )

.set pwd $pwd
.set cp  $pc

