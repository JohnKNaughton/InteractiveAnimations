"""Pull card text, costs and numbers out of the installed game, for the hover cards.

Everything the card tooltip shows comes from the game's own files:

* names, descriptions and keyword text: ``localization/eng/cards.json`` and
  ``card_keywords.json`` inside ``SlayTheSpire2.pck`` (an unencrypted Godot pack).
  Descriptions are templates - ``Deal {Damage:diff()} damage.`` - so they need the
  numbers before they read as text.
* cost, type, rarity, keywords, the numbers, and what an upgrade changes: these
  exist only in the compiled ``sts2.dll`` (the C# source files in the pack are empty
  stubs). Each card is a class whose constructor passes ``(cost, type, rarity,
  target, ...)`` to ``CardModel``, whose ``CanonicalVars`` builds its numbers and
  whose ``OnUpgrade`` adjusts them. The IL for those methods is small and very
  regular, so a tiny stack interpreter reads it.
* which character a card belongs to: the folder its portrait lives in.

The output, ``sts2_cards.js`` (``const CARD_INFO``), is keyed by the same upper-case
ids as the run files (``DEFRAGMENT``).

Needs ``pip install dnfile dncil``. Re-run after a game patch:

    python tools/sts2_cards.py
    python tools/sts2_cards.py --check     # list anything the extractor could not resolve
"""

import argparse
import collections
import io
import json
import os
import re
import struct
import sys

import dnfile
from dncil.cil.body import CilMethodBody
from dncil.cil.body.reader import CilMethodBodyReaderBase
from dncil.clr.token import Token

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JS = os.path.join(ROOT, "sts2_cards.js")
GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Slay the Spire 2"

CARD_TYPES = ["None", "Attack", "Skill", "Power", "Status", "Curse", "Quest"]
RARITIES = ["None", "Basic", "Common", "Uncommon", "Rare", "Ancient", "Event", "Token", "Status", "Curse", "Quest"]
TARGETS = ["None", "Self", "AnyEnemy", "AllEnemies", "RandomEnemy", "AnyPlayer", "AnyAlly",
           "AllAllies", "TargetedNoCreature", "Osty"]
KEYWORDS = ["None", "Exhaust", "Ethereal", "Innate", "Unplayable", "Retain", "Sly", "Eternal"]


# ── the Godot pack ────────────────────────────────────────────────────
class Pck:
    def __init__(self, path):
        self.f = open(path, "rb")
        head = self.f.read(112)
        assert head[:4] == b"GDPC", "not a Godot pack"
        self.base, dir_offset = struct.unpack("<QQ", head[24:40])
        self.f.seek(dir_offset)
        count = struct.unpack("<I", self.f.read(4))[0]
        self.index = {}
        for _ in range(count):
            n = struct.unpack("<I", self.f.read(4))[0]
            name = self.f.read(n).rstrip(b"\0").decode("utf8", "replace")
            off, size = struct.unpack("<QQ", self.f.read(16))
            self.f.read(16)
            flags = struct.unpack("<I", self.f.read(4))[0]
            assert not flags & 1, "encrypted pack"
            self.index[name] = (off, size)

    def read(self, name):
        off, size = self.index[name]
        self.f.seek(off + self.base)
        return self.f.read(size)

    def json(self, name):
        return json.loads(self.read(name).decode("utf-8-sig"))


# ── the assembly ──────────────────────────────────────────────────────
class Reader(CilMethodBodyReaderBase):
    def __init__(self, pe, row):
        self.pe = pe
        self.offset = pe.get_offset_from_rva(row.Rva)

    def read(self, n):
        data = self.pe.get_data(self.pe.get_rva_from_offset(self.offset), n)
        self.offset += n
        return data

    def tell(self):
        return self.offset

    def seek(self, offset):
        self.offset = offset
        return self.offset


def compressed(b, i):
    x = b[i]
    if x & 0x80 == 0:
        return x, i + 1
    if x & 0xC0 == 0x80:
        return ((x & 0x3F) << 8) | b[i + 1], i + 2
    return ((x & 0x1F) << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3], i + 4


class Asm:
    def __init__(self, path):
        self.pe = dnfile.dnPE(path)
        md = self.pe.net.mdtables
        self.types = md.TypeDef.rows
        self.methoddef = md.MethodDef.rows
        self.memberref = md.MemberRef.rows
        self.typeref = md.TypeRef.rows
        self.owner = {}
        for t in self.types:
            for m in t.MethodList:
                self.owner[id(m.row)] = t
        self.by_name = {}
        for t in self.types:
            self.by_name.setdefault(str(t.TypeName), t)
        self._strings = {}

    def methods(self, trow):
        return {str(m.row.Name): m.row for m in trow.MethodList}

    def body(self, mrow):
        return CilMethodBody(Reader(self.pe, mrow)) if mrow.Rva else None

    def user_string(self, tok):
        try:
            item = self.pe.net.user_strings.get(tok.rid)
            if item is None:
                return None
            raw = item.value if hasattr(item, "value") else item
            if isinstance(raw, (bytes, bytearray)):
                return bytes(raw).decode("utf-16-le", "replace").rstrip(chr(0) + chr(1))
            return str(raw)
        except Exception:
            return None

    def _coded_name(self, v):
        tag, rid = v & 3, v >> 2
        if tag == 0:
            return str(self.types[rid - 1].TypeName)
        if tag == 1:
            return str(self.typeref[rid - 1].TypeName)
        return "?"

    def _typespec(self, row):
        b = bytes(row.Signature.value) if hasattr(row.Signature, "value") else bytes(row.Signature)
        if b[0] != 0x15:
            return "?"
        i = 2
        v, i = compressed(b, i)
        base = self._coded_name(v)
        n, i = compressed(b, i)
        args = []
        for _ in range(n):
            k = b[i]
            i += 1
            if k in (0x11, 0x12):
                v, i = compressed(b, i)
                args.append(self._coded_name(v))
            else:
                args.append("?")
        return "%s<%s>" % (base, ",".join(args))

    @staticmethod
    def _param_count(sig):
        b = bytes(sig.value) if hasattr(sig, "value") else bytes(sig)
        i = 1
        if b[0] & 0x10:                       # generic method: skip the type-parameter count
            _, i = compressed(b, i)
        n, _ = compressed(b, i)
        return n

    def callee(self, tok):
        """Token -> (Owner or Owner<Arg>, method name, parameter count)."""
        if tok.table == 0x06:
            m = self.methoddef[tok.rid - 1]
            o = self.owner.get(id(m))
            return (str(o.TypeName) if o else "?", str(m.Name), self._param_count(m.Signature))
        if tok.table == 0x0A:
            m = self.memberref[tok.rid - 1]
            cls = m.Class.row
            owner = str(cls.TypeName) if hasattr(cls, "TypeName") else self._typespec(cls)
            return (owner, str(m.Name), self._param_count(m.Signature))
        return ("?", "?", 0)

    def field(self, tok):
        if tok.table == 0x0A:
            m = self.memberref[tok.rid - 1]
            cls = m.Class.row
            return (str(getattr(cls, "TypeName", "?")), str(m.Name))
        return ("?", "?")


INT_OPS = {"ldc.i4.m1": -1, **{"ldc.i4.%d" % i: i for i in range(9)}}
DEC = collections.namedtuple("DEC", "v")        # a System.Decimal literal
OBJ = object()


def literal_dec(args):
    """System.Decimal(int) or System.Decimal(lo, mid, hi, isNegative, scale) -> float/int."""
    if len(args) == 1:
        return args[0]
    lo, mid, hi, neg, scale = args
    n = ((hi & 0xFFFFFFFF) << 64) | ((mid & 0xFFFFFFFF) << 32) | (lo & 0xFFFFFFFF)
    v = n / (10 ** scale)
    return -v if neg else v


def tidy(v):
    return int(v) if float(v).is_integer() else round(float(v), 4)


def run_il(asm, mrow, on_newobj=None):
    """Interpret the straight-line IL these tiny methods are made of.

    Returns (events, unsupported). `events` is whatever on_newobj collected;
    `unsupported` lists any instruction outside the handful this understands.
    """
    body = asm.body(mrow)
    stack, bad = [], []
    ok = True
    events = []
    for ins in body.instructions:
        n = ins.opcode.name
        op = ins.operand
        if n in INT_OPS:
            stack.append(INT_OPS[n])
        elif n in ("ldc.i4.s", "ldc.i4"):
            stack.append(int(op))
        elif n in ("ldc.r4", "ldc.r8"):
            stack.append(float(op))
        elif n == "ldstr":
            stack.append(asm.user_string(op) if isinstance(op, Token) else str(op))
        elif n == "ldsfld":
            owner, name = asm.field(op) if isinstance(op, Token) else ("?", "?")
            if owner == "Decimal" and name in ("One", "Zero", "MinusOne"):
                stack.append(DEC({"One": 1, "Zero": 0, "MinusOne": -1}[name]))
            else:
                stack.append(OBJ)
        elif n == "dup":
            stack.append(stack[-1] if stack else OBJ)
        elif n in ("ldarg.0", "ldnull", "ldftn", "ldtoken"):
            stack.append(OBJ)
        elif n == "newarr":
            if stack:
                stack.pop()
            stack.append(OBJ)
        elif n.startswith("stelem"):
            for _ in range(3):
                if stack:
                    stack.pop()
        elif n == "newobj":
            owner, name, count = asm.callee(op)
            args = [stack.pop() if stack else OBJ for _ in range(count)][::-1]
            if owner == "Decimal":
                stack.append(DEC(literal_dec([a for a in args if isinstance(a, (int, float))])))
            else:
                if on_newobj:
                    events.append(on_newobj(owner, args))
                stack.append(OBJ)
        elif n in ("brtrue", "brtrue.s", "brfalse", "brfalse.s", "pop", "stsfld", "stloc.0", "stloc.1", "stloc.s"):
            # the lazy-delegate caching C# emits around lambdas: `cache ?? (cache = new Func(..))`.
            # Running it straight through (never taking the branch) leaves the stack as the
            # fall-through path would.
            if stack:
                stack.pop()
        elif n in ("call", "callvirt") and isinstance(op, Token):
            owner, name, count = asm.callee(op)
            if owner.endswith("Var") and name.startswith(("With", "From")):
                for _ in range(count):               # fluent setter: takes an argument, returns the var
                    if stack:
                        stack.pop()
            else:
                bad.append("%s::%s" % (owner, name))
        elif n in ("br", "br.s", "ret", "nop"):
            pass
        elif n in ("ldloc.0", "ldloc.1", "ldloc.s", "ldsflda", "ldfld"):
            stack.append(OBJ)
        else:
            bad.append(n)
    return events, bad


# ── card data ─────────────────────────────────────────────────────────
def snake(camel):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "_", camel).upper()


class Cards:
    def __init__(self, asm):
        self.asm = asm
        self._var_names = {}

    @staticmethod
    def var_default_name(tname):
        """DamageVar -> 'Damage'. (Each class's own constructors pass the same word along.)"""
        return tname[:-3] if tname.endswith("Var") and tname != "Var" else tname

    def is_var(self, owner):
        base = owner.split("<")[0]
        return base.endswith("Var") or base.startswith("PowerVar") or base == "DynamicVar"

    def vars_of(self, mrow):
        def on_new(owner, args):
            if not self.is_var(owner):
                return None
            nums = [a for a in args if isinstance(a, (int, float, DEC))]
            strs = [a for a in args if isinstance(a, str)]
            value = None
            for a in nums:
                value = a.v if isinstance(a, DEC) else a
                break
            if owner.startswith("PowerVar"):
                name = owner.split("<")[1].rstrip(">")
            else:
                name = strs[0] if strs else self.var_default_name(owner)
            return (name or owner, owner, value)
        events, bad = run_il(self.asm, mrow, on_new)
        return [e for e in events if e], bad

    def keywords_of(self, mrow):
        """The keyword ids a get_CanonicalKeywords body names."""
        out, prev = [], None
        for ins in self.asm.body(mrow).instructions:
            n = ins.opcode.name
            if n in INT_OPS or n in ("ldc.i4.s", "ldc.i4"):
                prev = INT_OPS.get(n, None) if n in INT_OPS else int(ins.operand)
            elif n.startswith("stelem") or n == "newobj":
                if prev is not None:
                    out.append(prev)
                prev = None
        # the array form pushes (length, then index/value pairs); keep values that are valid keywords
        return [KEYWORDS[k] for k in out if 0 < k < len(KEYWORDS)]

    def upgrade_of(self, mrow, var_names):
        """-> ({var: delta}, cost_delta, keywords_added, keywords_removed, ok)."""
        deltas = collections.Counter()
        cost, added, removed = 0, [], []
        last_var, last_num, last_str, last_int = None, None, None, None
        ok = True
        for ins in self.asm.body(mrow).instructions:
            n, op = ins.opcode.name, ins.operand
            if n in INT_OPS:
                last_int = INT_OPS[n]
            elif n in ("ldc.i4.s", "ldc.i4"):
                last_int = int(op)
            elif n == "ldstr":
                last_str = self.asm.user_string(op)
            elif n == "ldsfld" and isinstance(op, Token):
                owner, name = self.asm.field(op)
                if owner == "Decimal":
                    last_num = {"One": 1, "Zero": 0, "MinusOne": -1}.get(name, last_num)
            elif n == "newobj" and isinstance(op, Token):
                owner, name, count = self.asm.callee(op)
                if owner == "Decimal":
                    last_num = last_int if count == 1 else last_num
            elif n in ("call", "callvirt") and isinstance(op, Token):
                owner, name, _ = self.asm.callee(op)
                if owner == "DynamicVarSet" and name.startswith("get_") and name != "get_Item":
                    prop = name[4:]
                    last_var = prop if prop in var_names else (prop + "Power" if prop + "Power" in var_names else prop)
                elif owner == "DynamicVarSet" and name == "get_Item":
                    last_var = last_str
                elif name == "UpgradeValueBy":
                    if last_var is not None and last_num is not None:
                        deltas[last_var] += last_num
                    else:
                        ok = False
                elif owner == "CardEnergyCost" and name == "UpgradeBy":
                    cost += last_int if last_int is not None else 0
                elif owner == "CardModel" and name == "AddKeyword" and last_int is not None:
                    added.append(KEYWORDS[last_int] if 0 < last_int < len(KEYWORDS) else "?")
                elif owner == "CardModel" and name == "RemoveKeyword" and last_int is not None:
                    removed.append(KEYWORDS[last_int] if 0 < last_int < len(KEYWORDS) else "?")
                elif name in ("get_DynamicVars", "get_EnergyCost"):
                    pass
                else:
                    ok = False
        return dict(deltas), cost, added, removed, ok


# ── text templates ────────────────────────────────────────────────────
def fmt(v):
    return str(tidy(v))


def close_of(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return j
    return -1


def split_top(s, sep="|"):
    parts, depth, cur = [], 0, []
    for ch in s:
        depth += (ch == "{") - (ch == "}")
        if ch == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


class Ctx:
    def __init__(self, vals, upgraded, target, flags):
        self.vals, self.upgraded, self.target, self.flags = vals, upgraded, target, flags
        self.problems = []


def render(tpl, ctx, current=None):
    """Fill a localization template. Icons come out as {E} (energy) and {S} (star)."""
    out, i = [], 0
    while i < len(tpl):
        if tpl[i] != "{":
            out.append(tpl[i])
            i += 1
            continue
        j = close_of(tpl, i)
        if j < 0:
            out.append(tpl[i])
            i += 1
            continue
        out.append(token(tpl[i + 1:j], ctx, current))
        i = j + 1
    return "".join(out)


def token(body, ctx, current):
    name, _, spec = body.partition(":")
    if name == "singleStarIcon":
        return "{S}"
    if name == "IfUpgraded" and spec.startswith("show:"):
        parts = split_top(spec[5:])
        branch = parts[0] if ctx.upgraded else (parts[1] if len(parts) > 1 else "")
        return render(branch, ctx, current)
    if name == "InCombat":                       # live-combat annotations: not shown on a reference card
        parts = split_top(spec)
        return render(parts[1], ctx, current) if len(parts) > 1 else ""
    if spec.startswith("cond:"):
        parts = split_top(spec[5:])
        on = ctx.flags.get(name, False)
        branch = parts[0] if on else (parts[1] if len(parts) > 1 else "")
        return render(branch, ctx, current)
    if spec.startswith("choose("):
        end = spec.index("):")
        opts = spec[len("choose("):end].split("|")
        texts = split_top(spec[end + 2:])
        if name == "TargetType":
            k = opts.index(ctx.target) if ctx.target in opts else len(opts)
        else:                                    # e.g. a choice that depends on a runtime card type
            k = len(texts) - 1
        return render(texts[k], ctx, current) if k < len(texts) else ""

    known = ("diff(", "inverseDiff(", "energyIcons(", "starIcons", "plural:", "show:")
    if name != "" and name not in ctx.vals and spec and not spec.startswith(known) \
            and not name.startswith("Calculated"):
        parts = split_top(spec)
        return render(parts[1], ctx, current) if len(parts) > 1 else ""
    if name == "":
        value = current
    else:
        value = ctx.vals.get(name)
        if value is None and name.startswith("Calculated"):
            value = ctx.vals.get("CalculationBase")        # what the card shows outside combat
    if spec.startswith("energyIcons("):
        arg = spec[len("energyIcons("):spec.index(")")]
        n = int(arg) if arg else (value if value is not None else 1)
        return "{E}" * int(n)
    if spec.startswith("plural:"):
        parts = split_top(spec[7:])
        one, many = parts[0], parts[1] if len(parts) > 1 else parts[0]
        return render(one if value == 1 else many, ctx, value)
    if value is None:
        ctx.problems.append(body)
        return "X"
    if spec.startswith("starIcons"):
        return "{S}" * int(value)
    return fmt(value)                            # diff(), inverseDiff() and bare names


# ── putting it together ───────────────────────────────────────────────
def build(game, check=False):
    pck = Pck(os.path.join(game, "SlayTheSpire2.pck"))
    asm = Asm(os.path.join(game, "data_sts2_windows_x86_64", "sts2.dll"))
    loc = pck.json("localization/eng/cards.json")
    kwtext = pck.json("localization/eng/card_keywords.json")
    names = {}
    for k, v in loc.items():
        cid, _, field = k.partition(".")
        names.setdefault(cid, {})[field] = v

    # which character a card belongs to = the folder of its portrait
    owner = {}
    for path in pck.index:
        m = re.match(r"images/packed/card_portraits/([a-z_]+)/([a-z0-9_]+)\.png\.import$", path)
        if m:
            owner[m.group(2).upper()] = m.group(1)

    cards = Cards(asm)
    by_flat = {cid.replace("_", "").lower(): cid for cid in names}
    out, problems = {}, collections.defaultdict(list)
    for t in asm.types:
        if not str(t.TypeNamespace).endswith("Models.Cards"):
            continue
        cls = str(t.TypeName)
        cid = by_flat.get(cls.lower())
        if cid is None or "title" not in names[cid]:
            continue
        ms = asm.methods(t)
        info = {"n": names[cid]["title"]}

        # constructor: base(cost, type, rarity, target, showInLibrary)
        ints = []
        for ins in asm.body(ms[".ctor"]).instructions:
            if ins.opcode.name in INT_OPS:
                ints.append(INT_OPS[ins.opcode.name])
            elif ins.opcode.name in ("ldc.i4.s", "ldc.i4"):
                ints.append(int(ins.operand))
        if len(ints) < 4:
            problems[cid].append("constructor not understood")
            continue
        cost, ctype, rarity, target = ints[:4]
        info["t"] = CARD_TYPES[ctype] if 0 <= ctype < len(CARD_TYPES) else "?"
        info["r"] = RARITIES[rarity] if 0 <= rarity < len(RARITIES) else "?"
        target_name = TARGETS[target] if 0 <= target < len(TARGETS) else "?"
        x_cost = "get_HasEnergyCostX" in ms
        info["c"] = "X" if x_cost else (cost if cost >= 0 else None)
        if "get_CanonicalStarCost" in ms:
            for ins in asm.body(ms["get_CanonicalStarCost"]).instructions:
                if ins.opcode.name in INT_OPS:
                    info["s"] = INT_OPS[ins.opcode.name]
                    break
        if cid in owner:
            info["ch"] = owner[cid]

        # numbers
        base_vars = {}
        if "get_CanonicalVars" in ms:
            found, bad = cards.vars_of(ms["get_CanonicalVars"])
            for name, owner_t, value in found:
                if value is not None:
                    base_vars[name] = value
            if bad:
                problems[cid].append("variables only partly read (" + ", ".join(sorted(set(bad))) + ")")
        kws = cards.keywords_of(ms["get_CanonicalKeywords"]) if "get_CanonicalKeywords" in ms else []
        deltas, cost_delta, added, removed, up_ok = ({}, 0, [], [], True)
        if "OnUpgrade" in ms:
            deltas, cost_delta, added, removed, up_ok = cards.upgrade_of(ms["OnUpgrade"], set(base_vars))
            if not up_ok:
                problems[cid].append("upgrade only partly read")

        template = names[cid].get("description", "")
        up_vars = {k: base_vars[k] + deltas.get(k, 0) for k in base_vars}
        for k, d in deltas.items():
            if k not in up_vars:
                problems[cid].append("upgrade touches unknown value " + k)
        flags = {}
        if "get_GainsBlock" in ms:
            for ins in asm.body(ms["get_GainsBlock"]).instructions:
                if ins.opcode.name in INT_OPS:
                    flags["GainsBlock"] = bool(INT_OPS[ins.opcode.name])
                    break
        c_base, c_up = Ctx(base_vars, False, target_name, flags), Ctx(up_vars, True, target_name, flags)
        info["d"] = render(template, c_base)
        up_text = render(template, c_up)
        if c_base.problems:
            problems[cid].append("unresolved: " + ", ".join(sorted(set(c_base.problems))))
        up_kws = [k for k in kws if k not in removed] + [k for k in added if k not in kws]
        if kws:
            info["k"] = kws
        up = {}
        if up_text != info["d"]:
            up["d"] = up_text
        if cost_delta and info["c"] not in (None, "X"):
            up["c"] = max(0, info["c"] + cost_delta)
        if up_kws != kws:
            up["k"] = up_kws
        if up:
            info["u"] = up
        out[cid] = info

    keywords = {}
    for k in KEYWORDS[1:]:
        key = k.upper()
        if key + ".title" in kwtext:
            keywords[k] = {"n": kwtext[key + ".title"], "d": kwtext.get(key + ".description", "")}
    return out, keywords, problems, set(names) - set(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", default=GAME, help="Slay the Spire 2 install folder")
    ap.add_argument("--check", action="store_true", help="print what could not be resolved, write nothing")
    args = ap.parse_args()
    out, keywords, problems, unmatched = build(args.game)
    print("cards: %d | with problems: %d | in localization but no class: %d" % (len(out), len(problems), len(unmatched)))
    if args.check or problems:
        for cid in sorted(problems)[:80]:
            print("  %-26s %s" % (cid, "; ".join(problems[cid])))
    if unmatched:
        print("  no class for:", ", ".join(sorted(unmatched)[:20]))
    if args.check:
        return 0
    payload = {"cards": out, "keywords": keywords}
    with io.open(OUT_JS, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("const CARD_INFO = ")
        json.dump(payload, fh, separators=(",", ":"), ensure_ascii=False)
        fh.write(";\n")
    print("wrote sts2_cards.js (%d KB)" % (os.path.getsize(OUT_JS) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
