# coding: utf-8

module ShuntingYard

  class << self

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

    def compile(lexed_infix_expression, config)

      operators_config = config[:operators].clone
      default_operator = config[:default_operator]
      escape_symbol = config[:escape_symbol] || '`'
      escaped_value = config[:escaped_value] || lambda { |s| s }

      representation_of = lambda do |something|
        if operators_config.has_key?(something)
          operators_config[something].symbol
        elsif something.is_a?(String)
          something
        else
          error(`#{something} is not a value`)
        end
      end

      type_of = lambda { |symbol| operators_config.has_key?(symbol) ? operators_config[symbol][:type] : 'value' }

      is_infix = lambda { |symbol| type_of[symbol]== 'infix' }
      is_prefix = lambda { |symbol| type_of[symbol]== 'prefix' }
      is_postfix = lambda { |symbol| type_of[symbol]== 'postfix' }
      is_combinator = lambda { |symbol| is_infix[symbol] || is_prefix[symbol] || is_postfix[symbol] }
      is_escape = lambda { |symbol| symbol == escape_symbol }
      awaits_value = lambda { |symbol| is_infix[symbol] || is_prefix[symbol] }

      operator_stack = []
      rpn = []
      awaiting_value = true

      while lexed_infix_expression.length > 0 do
        symbol = lexed_infix_expression.shift

        if is_escape[symbol]
          if lexed_infix_expression.empty?
            error('Escape symbol #{escape_symbol} has no following symbol')
          else
            value_symbol = lexed_infix_expression.shift

            if awaiting_value
              # push the escaped value of the symbol

              rpn.push(escaped_value[value_symbol])
            else
              # value catenation

              lexed_infix_expression.unshift(value_symbol)
              lexed_infix_expression.unshift(escape_symbol)
              lexed_infix_expression.unshift(default_operator)
            end
            awaiting_value = false
          end
        elsif symbol == '(' && awaiting_value
          # opening parenthesis case, going to build
          # a value
          operator_stack.push(symbol)
          awaiting_value = true
        elsif symbol == '('
          # value catenation

          lexed_infix_expression.unshift(symbol)
          lexed_infix_expression.unshift(default_operator)
          awaiting_value = false
        elsif symbol == ')'
          # closing parenthesis case, clear the
          # operator stack

          while operator_stack.length > 0 && operator_stack.last != '(' do
            op = operator_stack.pop

            rpn.push(representation_of[op])
          end

          if operator_stack.last == '('
            operator_stack.pop
            awaiting_value = false
          else
            error('Unbalanced parentheses')
          end
        elsif is_prefix[symbol]
          if awaiting_value
            precedence = operators_config[symbol][:precedence]

            # pop higher-precedence operators off the operator stack
            while is_combinator[symbol] && operator_stack.length > 0 && operator_stack.last != '(' do
              opPrecedence = operators_config[operator_stack.last][:precedence]

              if precedence < opPrecedence
                op = operator_stack.pop

                rpn.push(representation_of[op])
              else
                break
              end
            end

            operator_stack.push(symbol)
            awaiting_value = awaits_value[symbol]
          else
            # value catenation

            lexed_infix_expression.unshift(symbol)
            lexed_infix_expression.unshift(default_operator)
            awaiting_value = false
          end
        elsif is_combinator[symbol]
          precedence = operators_config[symbol][:precedence]

          # pop higher-precedence operators off the operator stack
          while is_combinator[symbol] && operator_stack.length > 0 && operator_stack.last != '(' do
            opPrecedence = operators_config[operator_stack.last][:precedence]

            if precedence < opPrecedence
              op = operator_stack.pop

              rpn.push(representation_of[op])
            else
              break
            end
          end

          operator_stack.push(symbol)
          awaiting_value = awaits_value[symbol]
        elsif awaiting_value
          # as expected, go straight to the output

          rpn.push(representation_of[symbol])
          awaiting_value = false
        else
          # value catenation

          lexed_infix_expression.unshift(symbol)
          lexed_infix_expression.unshift(default_operator)
          awaiting_value = false
        end
      end

      # pop remaining symbols off the stack and push them
      while operator_stack.length > 0 do
        op = operator_stack.pop

        if operators_config.has_key?(op)
          opSymbol = operators_config[op][:symbol]
          rpn.push(opSymbol)
        else
          error(`Don't know how to push operator #{op}`)
        end
      end

      rpn
    end


    private

    def error(message)
      STDERR.puts message
      raise message
    end

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
    default_operator: '*',
    toValue: lambda { |n| +(n.to_i) }
  }

end

ShuntingYard::lex(ShuntingYard::ARITHMETIC, '(1*2)/3*4!')
