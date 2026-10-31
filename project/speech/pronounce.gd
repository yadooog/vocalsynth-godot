class_name Pronounce
## English spelling to sounds (ARPAbet phonemes, with a stress digit on vowels: 1 stressed,
## 0 unstressed, 2 secondary). Ported from the web game's shared/pronounce.js.
## Common words come from a small dictionary (English spelling is too irregular for rules
## alone); anything else goes through spelling rules (magic e, igh, tion, ee/ea/oo, th/sh/ch...).

# Word, then its phonemes. Add more any time: one line each.
const DICT_TEXT := """
a AH0
about AH0 B AW1 T
after AE1 F T ER0
again AH0 G EH1 N
all AO1 L
also AO1 L S OW0
always AO1 L W EY2 Z
am AE1 M
an AE1 N
and AE1 N D
any EH1 N IY0
anyone EH1 N IY0 W AH2 N
anybody EH1 N IY0 B AA2 D IY0
are AA1 R
around ER0 AW1 N D
as AE1 Z
ask AE1 S K
at AE1 T
away AH0 W EY1
awesome AO1 S AH0 M
baby B EY1 B IY0
back B AE1 K
bad B AE1 D
banana B AH0 N AE1 N AH0
be B IY1
beautiful B Y UW1 T AH0 F AH0 L
because B IH0 K AH1 Z
been B IH1 N
before B IH0 F AO1 R
best B EH1 S T
big B IH1 G
birthday B ER1 TH D EY2
boy B OY1
bread B R EH1 D
brother B R AH1 DH ER0
but B AH1 T
by B AY1
bye B AY1
call K AO1 L
came K EY1 M
can K AE1 N
can't K AE1 N T
cat K AE1 T
cheese CH IY1 Z
chicken CH IH1 K AH0 N
come K AH1 M
cool K UW1 L
could K UH1 D
crazy K R EY1 Z IY0
cute K Y UW1 T
dad D AE1 D
day D EY1
did D IH1 D
didn't D IH1 D AH0 N T
do D UW1
does D AH1 Z
dog D AO1 G
doing D UW1 IH0 NG
don't D OW1 N T
done D AH1 N
down D AW1 N
eat IY1 T
every EH1 V R IY0
everyone EH1 V R IY0 W AH2 N
everybody EH1 V R IY0 B AA2 D IY0
everything EH1 V R IY0 TH IH2 NG
eyes AY1 Z
face F EY1 S
father F AA1 DH ER0
feel F IY1 L
find F AY1 N D
fine F AY1 N
first F ER1 S T
fish F IH1 SH
food F UW1 D
for F AO1 R
friend F R EH1 N D
friends F R EH1 N D Z
from F R AH1 M
fun F AH1 N
funny F AH1 N IY0
game G EY1 M
get G EH1 T
girl G ER1 L
give G IH1 V
go G OW1
going G OW1 IH0 NG
gone G AO1 N
good G UH1 D
goodbye G UH2 D B AY1
got G AA1 T
great G R EY1 T
had HH AE1 D
happy HH AE1 P IY0
has HH AE1 Z
have HH AE1 V
he HH IY1
head HH EH1 D
hear HH IY1 R
heart HH AA1 R T
hello HH AH0 L OW1
help HH EH1 L P
her HH ER1
here HH IY1 R
hey HH EY1
hi HH AY1
him HH IH1 M
his HH IH1 Z
home HH OW1 M
hot HH AA1 T
house HH AW1 S
how HH AW1
hungry HH AH1 NG G R IY0
i AY1
i'm AY1 M
if IH1 F
in IH1 N
is IH1 Z
isn't IH1 Z AH0 N T
it IH1 T
it's IH1 T S
just JH AH1 S T
keep K IY1 P
kind K AY1 N D
know N OW1
laugh L AE1 F
let L EH1 T
let's L EH1 T S
life L AY1 F
like L AY1 K
listen L IH1 S AH0 N
little L IH1 T AH0 L
look L UH1 K
lol L AA1 L
love L AH1 V
lovely L AH1 V L IY0
made M EY1 D
make M EY1 K
man M AE1 N
many M EH1 N IY0
maybe M EY1 B IY0
me M IY1
mean M IY1 N
meet M IY1 T
mine M AY1 N
money M AH1 N IY0
more M AO1 R
morning M AO1 R N IH0 NG
mother M AH1 DH ER0
mouth M AW1 TH
much M AH1 CH
mum M AH1 M
music M Y UW1 Z IH0 K
my M AY1
name N EY1 M
need N IY1 D
never N EH1 V ER0
new N UW1
nice N AY1 S
night N AY1 T
no N OW1
nobody N OW1 B AA2 D IY0
not N AA1 T
nothing N AH1 TH IH0 NG
now N AW1
of AH1 V
off AO1 F
oh OW1
ok OW1 K EY1
okay OW1 K EY1
old OW1 L D
on AA1 N
once W AH1 N S
one W AH1 N
only OW1 N L IY0
or AO1 R
other AH1 DH ER0
our AW1 ER0
out AW1 T
over OW1 V ER0
people P IY1 P AH0 L
person P ER1 S AH0 N
play P L EY1
please P L IY1 Z
pretty P R IH1 T IY0
put P UH1 T
really R IH1 L IY0
right R AY1 T
said S EH1 D
say S EY1
see S IY1
she SH IY1
should SH UH1 D
sing S IH1 NG
sister S IH1 S T ER0
so S OW1
some S AH1 M
someone S AH1 M W AH2 N
something S AH1 M TH IH2 NG
song S AO1 NG
sorry S AA1 R IY0
stop S T AA1 P
sure SH UH1 R
take T EY1 K
talk T AO1 K
tell T EH1 L
thank TH AE1 NG K
thanks TH AE1 NG K S
that DH AE1 T
that's DH AE1 T S
the DH AH0
their DH EH1 R
them DH EH1 M
then DH EH1 N
there DH EH1 R
these DH IY1 Z
they DH EY1
thing TH IH1 NG
things TH IH1 NG Z
think TH IH1 NG K
this DH IH1 S
those DH OW1 Z
three TH R IY1
time T AY1 M
to T UW1
today T AH0 D EY1
together T AH0 G EH1 DH ER0
tomorrow T AH0 M AA1 R OW2
tongue T AH1 NG
tongues T AH1 NG Z
too T UW1
two T UW1
up AH1 P
us AH1 S
very V EH1 R IY0
voice V OY1 S
want W AA1 N T
was W AA1 Z
water W AO1 T ER0
way W EY1
we W IY1
weird W IH1 R D
welcome W EH1 L K AH0 M
well W EH1 L
went W EH1 N T
were W ER1
what W AH1 T
what's W AH1 T S
when W EH1 N
where W EH1 R
which W IH1 CH
who HH UW1
why W AY1
will W IH1 L
with W IH1 DH
won't W OW1 N T
world W ER1 L D
would W UH1 D
wow W AW1
yeah Y AE1
yes Y EH1 S
yo Y OW1
you Y UW1
you're Y UH1 R
your Y AO1 R
four F AO1 R
five F AY1 V
six S IH1 K S
seven S EH1 V AH0 N
eight EY1 T
nine N AY1 N
ten T EH1 N
zero Z IH1 R OW0
"""

const NUMBERS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

# [letters, phonemes, when]: tried in this order (longest first). `when`: "" always,
# "start2" only as a word's first two letters, "end" only at the end, "notv" only before a
# consonant, "end4" at the end of a word longer than 3, "es"/"le" the same plus a consonant before.
const RULES := [
	["tion", "SH AH0 N", ""],
	["sion", "ZH AH0 N", ""],
	["ture", "CH ER0", ""],
	["ough", "AO1", ""],
	["augh", "AO1", ""],
	["eigh", "EY1", ""],
	["igh", "AY1", ""],
	["tch", "CH", ""],
	["dge", "JH", ""],
	["sch", "S K", ""],
	["ch", "CH", ""],
	["sh", "SH", ""],
	["ph", "F", ""],
	["wh", "W", ""],
	["ck", "K", ""],
	["ng", "NG", ""],
	["qu", "K W", ""],
	["kn", "N", "start2"],
	["wr", "R", "start2"],
	["gn", "N", "start2"],
	["th", "TH", ""],
	["ee", "IY1", ""],
	["ea", "IY1", ""],
	["ie", "IY1", ""],
	["ei", "EY1", ""],
	["oo", "UW1", ""],
	["ou", "AW1", ""],
	["ow", "OW1", "end"],
	["ow", "AW1", ""],
	["oi", "OY1", ""],
	["oy", "OY1", ""],
	["ai", "EY1", ""],
	["ay", "EY1", ""],
	["au", "AO1", ""],
	["aw", "AO1", ""],
	["ew", "UW1", ""],
	["ue", "UW1", ""],
	["oa", "OW1", ""],
	["ar", "AA1 R", "notv"],
	["or", "AO1 R", "notv"],
	["er", "ER0", "notv"],
	["ir", "ER1", "notv"],
	["ur", "ER1", "notv"],
	["ed", "D", "end4"],
	["es", "Z", "es"],
	["le", "AH0 L", "le"],
	["ll", "L", ""],
	["ss", "S", ""],
	["ff", "F", ""],
	["tt", "T", ""],
	["pp", "P", ""],
	["dd", "D", ""],
	["bb", "B", ""],
	["gg", "G", ""],
	["mm", "M", ""],
	["nn", "N", ""],
	["rr", "R", ""],
	["zz", "Z", ""],
	["cc", "K", ""],
	["mb", "M", "end"],
	["ey", "IY0", "end4"],
]

const LONG := {"a": "EY1", "e": "IY1", "i": "AY1", "o": "OW1", "u": "UW1"}
const SHORT := {"a": "AE1", "e": "EH1", "i": "IH1", "o": "AA1", "u": "AH1", "y": "IH1"}
const CONS := {"b": "B", "c": "K", "d": "D", "f": "F", "g": "G", "h": "HH", "j": "JH", "k": "K", "l": "L", "m": "M",
	"n": "N", "p": "P", "q": "K", "r": "R", "s": "S", "t": "T", "v": "V", "w": "W", "x": "K S", "y": "Y", "z": "Z"}

static var _dict := {}


static func _words() -> Dictionary:
	if _dict.is_empty():
		for line in DICT_TEXT.strip_edges().split("\n"):
			var parts := line.strip_edges().split(" ", false)
			if parts.size() > 1:
				_dict[parts[0]] = Array(parts.slice(1))
	return _dict


static func _ch(w: String, i: int) -> String:
	return w[i] if i >= 0 and i < w.length() else ""


static func _is_v(c: String) -> bool:
	return c != "" and "aeiou".contains(c)


static func _rule_ok(kind: String, w: String, i: int) -> bool:
	match kind:
		"":
			return true
		"start2":
			return i == 2
		"end":
			return i == w.length()
		"notv":
			return not _is_v(_ch(w, i))
		"end4":
			return i == w.length() and w.length() > 3
		"es":
			return i == w.length() and w.length() > 3 and not _is_v(_ch(w, i - 3)) and _ch(w, i - 3) != "s"
		"le":
			return i == w.length() and w.length() > 3 and not _is_v(_ch(w, i - 3))
	return false


static func _in(c: String, letters: String) -> bool:
	return c != "" and letters.contains(c)


## Spelling rules, for words not in the dictionary.
static func spell(word: String) -> Array:
	var w := ""
	for c in word.to_lower():
		if c >= "a" and c <= "z":
			w += c
	var out: Array = []
	var magic := -1
	var n := w.length()
	if n > 3 and _is_v(_ch(w, n - 3)) and not _in(_ch(w, n - 2), "aeiouy") and w.ends_with("e"):
		magic = n - 3
	var i := 0
	while i < n:
		var ch := w[i]
		if ch == "e" and i == n - 1 and n > 2:
			break # silent final e
		var matched := false
		for r in RULES:
			var letters: String = r[0]
			if w.substr(i, letters.length()) == letters and _rule_ok(r[2], w, i + letters.length()):
				out.append_array(Array((r[1] as String).split(" ")))
				i += letters.length()
				matched = true
				break
		if matched:
			continue
		if i == magic and LONG.has(ch):
			out.append(LONG[ch])
		elif ch == "y":
			if i == 0 and _is_v(_ch(w, 1)):
				out.append("Y")
			elif i == n - 1:
				out.append("AY1" if n <= 3 else "IY0")
			else:
				out.append("IH1")
		elif ch == "c":
			out.append("S" if _in(_ch(w, i + 1), "eiy") else "K")
		elif ch == "g":
			out.append("JH" if _in(_ch(w, i + 1), "eiy") and i > 0 else "G")
		elif SHORT.has(ch):
			out.append(SHORT[ch])
		elif CONS.has(ch):
			out.append_array(Array((CONS[ch] as String).split(" ")))
		i += 1
	# One main stress per word (the first one). Short vowels elsewhere relax towards "uh".
	var stressed := false
	var result: Array = []
	for p in out:
		if not is_vowel(p):
			result.append(p)
			continue
		if p.ends_with("1") and not stressed:
			stressed = true
			result.append(p)
			continue
		var base: String = p.left(p.length() - 1)
		if base in ["AE", "EH", "AA", "AH", "UH"]:
			result.append("AH0")
		else:
			result.append(base + ("2" if p.ends_with("1") else p.right(1)))
	return result


## A word to its phonemes.
static func pronounce(word: String) -> Array:
	var w := word.to_lower()
	var d := _words()
	if d.has(w):
		return (d[w] as Array).duplicate()
	if w.is_valid_int():
		var out: Array = []
		for c in w:
			out.append_array(d.get(NUMBERS[int(c)], []))
		return out
	if w.ends_with("'s") and d.has(w.left(w.length() - 2)):
		return (d[w.left(w.length() - 2)] as Array) + ["Z"]
	return spell(w)


static func is_vowel(p: String) -> bool:
	var last := p.right(1)
	return last != "" and last >= "0" and last <= "9"
