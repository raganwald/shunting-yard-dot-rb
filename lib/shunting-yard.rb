# coding: utf-8

module ShuntingYard
  # takes as input raw text, returns an array of symbols
  # config.operators is a dictionary, with each key being an operator
  # this version only supports single-character operators
  def lex(config, raw)
    operators = config[:operators].keys.map(&:to_s)
    parentheses = ['(', ')']
    significant_characters = operators.concat(parentheses)

    # split on whitespace
    strings = raw.split /\s+/

    split_strings_on_significant_characters(strings, significant_characters)
  end

  module_function :lex

  ARITHMETIC = {
    operators: {
      '+' => {
        symbol: :+,
        type: 'infix',
        precedence: 1,
        fn: lambda { |a, b| a + b }
      },
      '-' => {
        symbol: :-,
        type: 'infix',
        precedence: 1,
        fn: lambda { |a, b| a - b }
      },
      '*' => {
        symbol: :*,
        type: 'infix',
        precedence: 3,
        fn: lambda { |a, b| a * b }
      },
      '/' => {
        symbol: :/,
        type: 'infix',
        precedence: 2,
        fn: lambda { |a, b| a / b }
      },
      '!' => {
        symbol: :!,
        type: 'postfix',
        precedence: 4,
        fn: lambda { |n| (1..n).reduce(&:*) }
      }
    },
    defaultOperator: '*',
    toValue: lambda { |n| +(n.to_i) }
  }

  private

  def split_strings_on_significant_characters(strings, characters = [])
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
  def split_on_a_significant_character(str, character)
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
