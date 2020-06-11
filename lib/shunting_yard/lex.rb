# coding: utf-8

module ShuntingYard
  # takes as input raw text, returns an array of symbols
  # config.operators is a dictionary, with each key being an operator
  # this version only supports single-character operators
  def self.lex(config, raw)
    operators = config[:operators].keys.map(&:to_s)
    parentheses = ['(', ')']
    significant_characters = operators.concat(parentheses)

    # split on whitespace
    strings = raw.split /\s+/

    split_strings_on_significant_characters(strings, significant_characters)
  end

  def self.split_strings_on_significant_characters(strings, characters = [])
    if characters.empty?
      strings
    else
      character = characters.first
      split_strings_on_significant_characters(
        strings.flat_map { |str| split_on_a_significant_character(str, character) },
        characters[1..-1]
      )
    end
  end

  # split the chunks around significant characters
  # but keep the characters
  def self.split_on_a_significant_character(str, character)
    if str.start_with?(character)
      [character].concat(split_on_a_significant_character(str[1..-1], character))
    elsif str.end_with?(character)
      split_on_a_significant_character(str[0..-2], character).concat([character])
    else
      chunks = str.split(character)
      first = chunks.first
      rest = chunks[1..-1].flat_map { |chunk| [character, chunk] }
      rest.unshift(first)
    end
  end
end
