/**
Copyright: Piotr Szturmaj 2012.
License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Piotr Szturmaj
*/

module json;

import std.algorithm, std.conv, std.exception, std.range, std.string, std.traits,
    std.typecons, std.typetuple, std.uni, std.utf, std.variant;

bool isJSONWhiteSpace(T)(T c)
    if (isSomeChar!T)
{
    return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}

template ByDchar(_R)
     if (isInputRange!_R)
{
    alias _R R;

    alias ElementType!R E;
    static if (is(Unqual!E == dchar))
    {
        alias R ByDchar;
    }
    else static if (is(Unqual!E == char))
    {
        struct ByDchar
        {
            char[6] buf; // max stride
            size_t len;
            size_t index = 0;
            dchar current = 0xFFFF;
            R r;

            this(_R r)
            {
                this.r = r;
                if (!this.r.empty)
                {
                    int i;
                    for (i = 0; i < 6 && !this.r.empty; i++, this.r.popFront())
                        buf[i] = this.r.front;
                    len = i;
                    current = decode(buf[0 .. len], index);
                }
            }

            bool empty() @property
            {
                return current == 0xFFFF;
            }

            dchar front() @property
            {
                return current;
            }

            void popFront()
            {
                if (index == len)
                {
                    if (len < 6)
                    {
                        current = 0xFFFF;
                        return;
                    }

                    // fill buf
                    int i;
                    for (i = 0; i < 6 && !this.r.empty; i++, this.r.popFront())
                        buf[i] = this.r.front;

                    if (i == 0)
                    {
                        current = 0xFFFF;
                        return;
                    }

                    index = 0;
                    len = i;
                }
                
                auto utfLen = stride(buf, index);
                assert(utfLen <= 6);

                if (index + utfLen > 6)
                {
                    // shift buf to the left and fill it up to its length
                    copy(cast(ubyte[])buf[index .. $], cast(ubyte[])buf[0 .. $ - index]);
                    len = 6 - index;
                    for (int i = 6 - index; i < 6 && !this.r.empty; i++, this.r.popFront())
                    {
                        buf[i] = this.r.front;
                        len++;
                    }
                    index = 0;
                }

                current = decode(buf[0 .. len], index);
            }
        }
    }
}

alias Variant[string] JSONObject;
alias Variant[] JSONArray;

template DUnion(TypeTag, Types...)
{
    struct DUnion
    {
        template SwapSelfComposite(Types...)
        {
            alias staticMap!(SwapSelf, Types) SwapSelfComposite;
        }

        template SwapSelf(T)
        {
            static if (hasIndirections!T)
            {
                static if (isPointer!T)
                    alias SwapSelf!(pointerTarget!T) SwapSelf;
                else static if (isDynamicArray!T)
                    alias SwapSelf!(typeof(T[0]))[] SwapSelf;
                else static if (is(T == class))
                    alias SwapSelfComposite!(T.tupleof) SwapSelf;
                else static if (isAssociativeArray!T)
                    alias SwapSelf!(typeof(T.values[0]))[SwapSelf!(typeof(T.keys[0]))] SwapSelf;
            }
            else
            {
                static if (is(T == Self))
                    alias DUnion SwapSelf;
                else static if (is(T == struct) || is(T == union))
                    alias SwapSelfComposite!(T.tupleof) SwapSelf;
                else
                    alias T SwapSelf;
            }
        }

        union
        {
            alias SwapSelfComposite!Types STypes;
            STypes types;
        }

        TypeTag type;

        this(T)(T v)
        {
            static if (!is(T == typeof(null)))
                _opAssign(v);
            else
                type = JSONType.nil;
        }

        auto as(T)() @property
        {
            enum idx = staticIndexOf!(T, STypes);
            static assert(idx >= 0);
            return types[idx];
        }

        auto _opAssign(T)(T v)
        {
            enum idx = staticIndexOf!(T, STypes);
            static assert(idx >= 0);
            type = cast(TypeTag)idx;
            return types[idx] = v;
        }

        string toString()
        {
            return .toString(this);
        }
    }
}

struct Self {}
enum JSONType { boolean, number, text, array, object, nil };
alias DUnion!(JSONType, bool, double, string, Self[], Self[string], /*dummy*/ ubyte*) JSONValue;

string toString(ref JSONValue v)
{
    final switch (v.type)
    {
        case JSONType.boolean: return to!string(v.as!bool);
        case JSONType.nil: return "null";
        case JSONType.number: return to!string(v.as!double);
        case JSONType.text: return "\"" ~ v.as!string ~ "\"";
        case JSONType.array:
            string s = "[";
            foreach (i, e; v.as!(JSONValue[]))
                s ~= (i > 0 ? ", " : "") ~ toString(e);
            s ~= "]";
            return s;
        case JSONType.object:
            string s = "{"; int i = 0;
            foreach (key, value; v.as!(JSONValue[string]))
                s ~= (i++ > 0 ? ", \"" : "\"") ~ key ~ "\": " ~ toString(value);
            s ~= "}";
            return s;
    }
}

struct JSONField
{
    string key;
    JSONValue value;
}

struct JSONString(Reader)
{
    Reader* r;

    byte _escaped;
    bool _empty;
    dchar _front;

    this(Reader* r)
    {
        this.r = r;
        enforce(r.r.front == '"');
        popFront();
    }

    auto whole() @property
    {
        static if (isSomeString!(typeof(r.r)))
        {
            if (empty)
                return r.r[0 .. 0];

            Appender!string app = void;
            bool appInitialized = false;
            auto slice = r.r[];
            for ( ; !empty; popFront())
            {
                if (_escaped)
                {
                    if (!appInitialized)
                    {
                        app = appender!string();
                        appInitialized = true;
                    }

                    auto len = slice.length - r.r.length;
                    if (len > 0)
                        app.put(slice[0 .. len - _escaped]);
                    app.put(front);
                    slice = r.r[1 .. $];
                }
            }

            auto len = slice.length - r.r.length - 1;
            if (appInitialized)
            {
                if (len > 0)
                    app.put(slice[0 .. len]);
                return app.data;
            }
            else
                return slice[0 .. len];
        }
        else
        {
            auto app = appender!string();
            for (; !empty; popFront())
                app.put(front);
            assert(empty);
            return app.data;
        }
    }

    bool empty() @property
    {
        return _empty;
    }

    dchar front() @property
    {
        return _front;
    }

    void popFront()
    {
        r.r.popFront();
        enforce(!r.r.empty);
        if (r.r.front == '"') {
            r.r.popFront();
            _empty = true;
        }
        else if (r.r.front == '\\')
        {
            // escaped
            r.r.popFront();
            enforce(!r.r.empty);
            _escaped = 1;

            switch (r.r.front)
            {
                case '"': _front = '"'; break;
                case '\\': _front = '\\'; break;
                case '/': _front = '/'; break;
                case 'b': _front = '\b'; break;
                case 'f': _front = '\f'; break;
                case 'n': _front = '\n'; break;
                case 'r': _front = '\r'; break;
                case 't': _front = '\t'; break;
                case 'u':
                    static if (isSomeString!(typeof(r.r)))
                    {
                        enforce(r.r.length >= 5);
                        _front = to!uint(r.r[1 .. 5], 16);
                        r.r = r.r[4 .. $];
                    }
                    else
                    {
                        dchar[4] buf = void;
                        foreach (i; 0 .. 4)
                        {
                            r.r.popFront();
                            enforce(!r.r.empty);
                            buf[i] = r.r.front;
                        }
                        _front = to!uint(buf[], 16);
                    }
                    _escaped = 5;
                    break;
                default: throw new Exception(format("Invalid escape character: \"%s\" (U+%04X)", r.r.front, cast(uint)r.r.front));
            }
        }
        else
        {
            // unescaped
            _escaped = 0;
            auto c = r.r.front;
            enforce(c >= 0x20, format("Unexpected control character: (U+%04X)", cast(uint)c));
            _front = c;
        }
    }
}

struct JSONMember(Reader)
{
    Reader* r;
    JSONString!Reader _name;
    JSONVal!Reader _value;

    this(Reader* r)
    {
        this.r = r;
    }

    JSONField whole() @property
    {
        return JSONField(name.whole, value.whole);
    }

    auto ref name() @property
    {
        _name = JSONString!Reader(r);
        return _name;
    }

    auto value() @property
    {
        r.skipWhitespace();
        enforce(r.r.front == ':', to!string(r.r.front));
        r.r.popFront();
        r.skipWhitespace();
        //_name.skip(); // skip was a dummy range consumption
        // I think this function should be added to Phobos
        enforce(_name.empty, "Name range must be consumed first");
        return JSONVal!Reader(r);
    }
}


struct JSONMembers(Reader)
{
    Reader* r;
    bool _empty;

    this(Reader* r)
    {
        this.r = r;
        r.skipWhitespace();
        _empty = r.r.front == '}';
    }

    bool empty() @property
    {
        return _empty;
    }

    auto front() @property
    {
        return JSONMember!Reader(r);
    }

    void popFront()
    {
        r.skipWhitespace();

        switch (r.r.front)
        {
            case ',':
                r.r.popFront();
                r.skipWhitespace();
                break;
            case '}':
                r.r.popFront();
                _empty = true;
                break;
            default:
                auto c = r.r.front;
                throw new Exception(format("A comma ',' or closing bracket '}' expected, not \"%s\" (U+%04X)",
                                           c, cast(uint)c));
        }
    }
}

JSONType firstCharToType(dchar c)
{
    switch (c)
    {
        case '{': return JSONType.object;
        case '[': return JSONType.array;
        case '"': return JSONType.text;
        case '-':
        case '0': .. case '9':
            return JSONType.number;
        case 'f', 't': return JSONType.boolean;
        case 'n': return JSONType.nil;
        default: throw new Exception(format("Invalid first character of JSON value: \"%s\" (U+%04X)", c, cast(uint)c));
    }
}

struct JSONNumber(Reader)
{
    Reader* r;
    uint stage;
    dchar last;
    bool _empty;

    /*
    stages:
    0 - minus
    1 - first digit
    2 - next digit
    3 - frac
    ...
    */

    this(Reader* r)
    {
        this.r = r;
        stage = r.r.front == '-' ? 0 : 1;
        // first char was validated with firstCharToType()
    }

    bool empty() @property
    {
        return r.r.empty && _empty;
    }

    dchar front() @property
    {
        return r.r.front;
    }

    bool _isDigit(dchar fd)(dchar c)
    {
        switch (c)
        {
            case fd: .. case '9': return true;
            default: return false;
        }
    }

    alias _isDigit!'0' isDigit;
    alias _isDigit!'1' isDigig19;

    void popFront()
    {
        r.r.popFront();
        if (stage != 1)
            enforce(!r.r.empty);
        else
            _empty = true;
        dchar c = r.r.front;

        switch (stage)
        {
            case 0:
                enforce(isDigit(c), format("Digit 0..9 expected, not \"%s\" (U+%04X)", c, cast(uint)c));
                stage++;
                last = c;
                break;
            case 1:
            case 2:
                switch (c)
                {
                    case '0': .. case '9':
                        if (stage == 1)
                        {
                            if (last == '0')
                                throw new Exception(format("A dot '.', 'e' or 'E' expected, not \"%s\" (U+%04X)", c, cast(uint)c));
                            stage++;
                        }
                        break;
                    case '.': stage = 3; break;
                    case 'e':
                    case 'E': stage = 4; break;
                    default: _empty = true;
                }
                break;
            case 3:
                enforce(isDigit(c), format("Digit 0..9 expected, not \"%s\" (U+%04X)", c, cast(uint)c));
                stage++;
                break;
            case 4:
                switch (c)
                {
                    case '0': .. case '9': break;
                    case 'e':
                    case 'E': stage = 5; break;
                    default: _empty = true;
                }
                break;
            case 5:
                switch (c)
                {
                    case '-':
                    case '+':
                    case '0': .. case '9': stage++; break;
                    default: _empty = true;
                }
                break;
            case 6:
                if (!isDigit(c))
                    _empty = true;
                break;
            default:
        }
    }
}

struct JSONVal(Reader)
{
    Reader* r;
    immutable JSONType peekType;

    this(Reader* r)
    {
        this.r = r;
        peekType = firstCharToType(r.r.front);
    }

    JSONValue whole() @property
    {
        final switch (peekType)
        {
            case JSONType.boolean:
                if (r.r.front == 't')
                {
                    r.expect("true");
                    return JSONValue(true);
                }
                else
                {
                    r.expect("false");
                    return JSONValue(false);
                }
            case JSONType.nil:
                r.expect("null");
                return JSONValue(null);
            case JSONType.number:
                auto n = JSONNumber!Reader(r);
                return JSONValue(parse!double(n));
            case JSONType.text:
                auto s = JSONString!Reader(r);
                return JSONValue(s.whole);
            case JSONType.array:
                JSONValue[] arr;
                foreach (front; byArrayElements)
                    arr ~= front.whole;
                return JSONValue(arr);
            case JSONType.object:
                JSONValue[string] map;
                foreach (front; byMembers)
                {
                    auto field = front.whole;
                    map[field.key] = field.value;
                }
                return JSONValue(map);
        }
    }

    auto byMembers() @property
    {
        enforce(peekType == JSONType.object);
        r.r.popFront();
        enforce(!r.r.empty);
        return JSONMembers!Reader(r);
    }

    auto byArrayElements() @property
    {
        enforce(peekType == JSONType.array);
        r.r.popFront();
        enforce(!r.r.empty);
        return JSONArrayElements!Reader(r);
    }
}

struct JSONArrayElements(Reader)
{
    Reader* r;
    bool _empty;

    this(Reader* r)
    {
        this.r = r;
        r.skipWhitespace();
        _empty = r.r.front == ']';
    }

    bool empty() @property
    {
        return _empty;
    }

    auto front() @property
    {
        return JSONVal!Reader(r);
    }

    void popFront()
    {
        r.skipWhitespace();

        switch (r.r.front)
        {
            case ',':
                r.r.popFront();
                r.skipWhitespace();
                break;
            case ']':
                r.r.popFront();
                _empty = true;
                break;
            default:
                auto c = r.r.front;
                throw new Exception(format("A comma ',' or closing bracket ']' expected, not \"%s\" (U+%04X)",
                                           c, cast(uint)c));
        }
    }
}

struct JSONReader(R)
    if (isInputRange!R && isSomeChar!(ElementType!R))
{
    alias ByDchar!R DR;
    DR r;

    this(DR r)
    {
        this.r = r;
        skipWhitespace();
        enforce(this.r.front == '{' || this.r.front == '[');
    }

    void skipWhitespace()
    {
        while (isJSONWhiteSpace(r.front) && !r.empty)
            r.popFront();
    }

    void expect(dstring s)
    {
        foreach (c; s)
        {
            enforce(!r.empty);
            enforce(r.front == c, format("Invalid characted '%s' near '%s%s', expected '%s'", r.front, s[0], array(take(r, 10)), s));
            r.popFront();
        }
    }

    auto value() @property
    {
        return JSONVal!(typeof(this))(&this);
    }
}