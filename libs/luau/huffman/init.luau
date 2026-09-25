const tree = require("@self/tree")
const codec = require("@self/codec")

return {
	create_tree = tree.create_tree,
	create_tree_from_string = tree.create_tree_from_string,

	traverse_tree = tree.traverse_tree,

	encode_symbols = codec.encode_symbols,
	decode_symbols = codec.decode_symbols,

	encode_string = codec.encode_string,
	decode_string = codec.decode_string,
}
