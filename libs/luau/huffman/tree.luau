export type HuffmanTreeNode<Symbol = any> = {
	freq: number,
	symbol: Symbol?,
	left: HuffmanTreeNode<Symbol> | any,
	right: HuffmanTreeNode<Symbol> | any,
}

const function pqinsert(queue: { HuffmanTreeNode }, node: HuffmanTreeNode)
	const node_freq = node.freq

	for index, other in queue do
		if node_freq > other.freq then
			table.insert(queue, index, node)
			return
		end
	end

	table.insert(queue, node)
end

const function create_tree<Symbol>(frequencies: { [Symbol]: number }): HuffmanTreeNode<Symbol>
	const queue: { HuffmanTreeNode<Symbol> } = {}

	for symbol, freq in frequencies do
		pqinsert(queue, { freq = freq, symbol = symbol })
	end

	assert(#queue > 0, "not enough frequency data to construct a huffman tree")

	while #queue > 1 do
		const left, right = table.remove(queue), table.remove(queue)
		pqinsert(queue, { freq = left.freq + right.freq, left = left, right = right })
	end

	return queue[1]
end

const function create_tree_from_string(str: string)
	const frequencies = {}

	for char in string.gmatch(str, ".") do
		frequencies[char] = (frequencies[char] or 0) + 1
	end

	return create_tree(frequencies)
end

const function traverse_tree<Symbol>(tree_root: HuffmanTreeNode<Symbol>, code: number, code_width: number): (Symbol, number)
	local bit_count = code_width
	local current_node = tree_root

	while current_node.symbol == nil do
		bit_count -= 1
		current_node = if bit32.btest(code, bit32.lshift(1, bit_count)) then current_node.right else current_node.left
	end

	return current_node.symbol, code_width - bit_count
end

return {
	create_tree = create_tree,
	create_tree_from_string = create_tree_from_string,

	traverse_tree = traverse_tree,
}
