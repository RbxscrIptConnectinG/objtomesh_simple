const function reader(stream: buffer)
	local read_bit_cursor = 0

	const function peek(amount_bits: number): number
		assert(amount_bits <= 32, "can't read more than 32 bits at once")

		const byte_use_count = 1 + (read_bit_cursor + amount_bits - 1) // 8 - read_bit_cursor // 8
		local read_value = 0

		for byte_offset = 0, byte_use_count - 1 do
			const byte_value = buffer.readu8(stream, read_bit_cursor // 8 + byte_offset)
			read_value = bit32.bor(bit32.lshift(read_value, 8), byte_value)
		end

		const field = byte_use_count * 8 - (read_bit_cursor % 8 + amount_bits)

		return bit32.extract(read_value, field, amount_bits)
	end

	const function shift(amount_bits: number): number
		read_bit_cursor += amount_bits

		return read_bit_cursor
	end

	return peek, shift
end

const function writer(stream: buffer)
	local write_bit_offset = 0
	local write_byte_offset = 0
	local write_register = 0

	const function flush()
		if write_register == 0 then
			return
		end

		buffer.writeu8(stream, write_byte_offset, write_register)
		write_register = 0
	end

	const function append(value: number, width: number)
		const shift_by = 8 - width - write_bit_offset
		const shifted_value = bit32.lshift(value, shift_by)
		write_register = bit32.bor(write_register, shifted_value)
		write_bit_offset += width

		if write_bit_offset >= 8 then
			flush()

			write_byte_offset += 1
			write_bit_offset = 0

			-- nondescript check
			-- if we've shifted right (negative) at all that means that information has been lost and needs to be appended separately
			-- otherwise we can exit early
			if shift_by >= 0 then
				return
			end

			const new_width = -shift_by
			const new_value = bit32.extract(value, 0, new_width)

			append(new_value, new_width)
		end
	end

	return append, flush
end

return {
	reader = reader,
	writer = writer,
}
