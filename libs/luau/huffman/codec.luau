--!nonstrict
const tree = require("./tree")
const traverse_tree = tree.traverse_tree

const bitstream = require("./bitstream")
const bitstream_writer = bitstream.writer
const bitstream_reader = bitstream.reader

type PrefixCode = {
	code: number,
	bit_count: number,
}

const function get_bit_width_range(symbol_mappings: { [any]: PrefixCode }): (number, number)
	local min_width, max_width = math.huge, 0

	for _, prefix in symbol_mappings do
		const bit_count = prefix.bit_count

		if bit_count < min_width then
			min_width = bit_count
		end

		if bit_count > max_width then
			max_width = bit_count
		end
	end

	return min_width, max_width
end

const function load_codes<Symbol>(
	node: tree.HuffmanTreeNode<Symbol>,
	output_symbol_mapping: { [Symbol]: PrefixCode },
	partial: PrefixCode
)
	if node.symbol ~= nil then
		output_symbol_mapping[node.symbol] = partial
	else
		const code, bit_count = partial.code, partial.bit_count
		load_codes(node.left, output_symbol_mapping, { code = code * 2, bit_count = bit_count + 1 })
		load_codes(node.right, output_symbol_mapping, { code = code * 2 + 1, bit_count = bit_count + 1 })
	end
end

const function get_symbol_mappings<Symbol>(tree: tree.HuffmanTreeNode<Symbol>): { [Symbol]: PrefixCode }
	if tree.symbol ~= nil then
		return {
			[tree.symbol] = { code = 0, bit_count = 1 },
		}
	end

	const symbol_mapping = {}

	load_codes(tree, symbol_mapping, { code = 0, bit_count = 0 })

	return symbol_mapping
end

const function get_total_bit_count<Symbol>(symbol_mappings: { [Symbol]: PrefixCode }, data: { Symbol }): number
	local bit_count = 0

	for _, symbol in data do
		const prefix = symbol_mappings[symbol]

		if prefix == nil then
			error(`invalid symbol '{symbol}'`)
		end

		bit_count += prefix.bit_count
	end

	return bit_count
end

const function get_total_bit_count_string(char_mappings: { [string]: PrefixCode }, str: string): number
	local bit_count = 0

	for char in string.gmatch(str, ".") do
		const prefix = char_mappings[char]

		if prefix == nil then
			error(`invalid character '{char}'`)
		end

		bit_count += prefix.bit_count
	end

	return bit_count
end

------------------------------------------------------------------------------------------------------------------------

const function decode_string(tree: tree.HuffmanTreeNode<string>, data: buffer): string
	const min_width, max_width = get_bit_width_range(get_symbol_mappings(tree))

	const total_bits = buffer.len(data) * 8
	local remaining_bits = total_bits

	local output_str = ""

	const peek, shift = bitstream_reader(data)

	while true do
		const bit_width = math.min(max_width, remaining_bits)

		const code = peek(bit_width)
		const char, bits_used = traverse_tree(tree, code, bit_width)
		output_str ..= char

		const current_bit_cursor = shift(bits_used)
		remaining_bits = total_bits - current_bit_cursor

		if remaining_bits < min_width then
			break
		end
	end

	return output_str
end

const function decode_symbols<Symbol>(tree: tree.HuffmanTreeNode<Symbol>, data: buffer): { Symbol }
	const total_bits = buffer.len(data) * 8
	local remaining_bits = total_bits

	const min_width, max_width = get_bit_width_range(get_symbol_mappings(tree))
	const symbol_array = {}

	const peek, shift = bitstream_reader(data)

	while true do
		const bit_width = math.min(max_width, remaining_bits)

		const code = peek(bit_width)
		const symbol, bits_used = traverse_tree(tree, code, bit_width)

		table.insert(symbol_array, symbol)

		const current_bit_cursor = shift(bits_used)
		remaining_bits = total_bits - current_bit_cursor

		if remaining_bits < min_width then
			break
		end
	end

	return symbol_array
end

const function encode_string(tree: tree.HuffmanTreeNode<string>, str: string): buffer
	const char_mapping = get_symbol_mappings(tree)

	const output_buffer = buffer.create(math.ceil(get_total_bit_count_string(char_mapping, str) / 8))
	const append, flush = bitstream_writer(output_buffer)

	for char in string.gmatch(str, ".") do
		const prefix = char_mapping[char]
		append(prefix.code, prefix.bit_count)
	end
	flush()

	return output_buffer
end

const function encode_symbols<Symbol>(tree: tree.HuffmanTreeNode<Symbol>, symbol_array: { Symbol }): buffer
	const symbol_mapping = get_symbol_mappings(tree)

	const output_buffer = buffer.create(math.ceil(get_total_bit_count(symbol_mapping, symbol_array) / 8))
	const append, flush = bitstream_writer(output_buffer)

	for _, symbol in symbol_array do
		const prefix = symbol_mapping[symbol]
		append(prefix.code, prefix.bit_count)
	end
	flush()

	return output_buffer
end

return {
	encode_string = encode_string,
	decode_string = decode_string,

	encode_symbols = encode_symbols,
	decode_symbols = decode_symbols,
}
