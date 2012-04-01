This is streaming json parser at early "alpha" stage. It returns slices when possible.
Benchmarked it and it's about 2.3x the speed of std.json.

It gives possibility to "dig" into the structure and stream (using ranges) by member fields,
array elements, or characters of field names and string values. It's possible to parse JSON
without a single allocation. For convenience, one can get objects, arrays and strings as a whole. 

TODOs:
- fix parsing of float exponents, but first check if they're really wrong :-)
- rename whole() functions to toObject, toArray, toJSONField, etc.
- cache returned objects to avoid crash when calling "whole" functions more than once
- use some range-lookahead construct to write more meaningful error messages
- create streaming writer (possibly reusing the same data structures)
- in writer add code to reserve empty whitespace bytes (typically between commas) to create
  possibility of changing json files in place
- make a possibility to specify a fixed-size buffer (e.g. 4K) to emplace returned data structures
  and strings. This is for avoiding allocations. If data structure is larger it might be allocated
  "naturally" or exception migh be thrown.
- make a possibility to map data type (such as struct or class) to JSON object and vice versa.
  For example: { "json": "string", "number": 5 } might be mapped to struct S { string json; double number; }
  It might be a source of optimization if data type is specified *before* parsing the structure. We don't
  want to convert JSONValue to struct, but we rather want to "fill" it directly from within parser.
- write XML and ASN.1 parsers using the same cascading-range approach ;-)