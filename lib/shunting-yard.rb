# coding: utf-8

module ShuntingYard

  class << self

    # takes as input raw text, returns an array of symbols
    # config.operators is a dictionary, with each key being an operator
    # this version only supports single-character operators
    def lex(config, input)
      error("Don't know how to lex #{input.inspect}") unless input.is_a?(String)

      operators = config[:operators].keys.map(&:to_s)
      parentheses = ['(', ')']
      significant_characters = operators.concat(parentheses)

      # split on whitespace
      strings = input.split /\s+/

      split_strings_on_significant_characters(strings, significant_characters)
    end

    def compile(config, input)
      if input.is_a?(String)
        compile(config, lex(config, input))
      elsif input.is_a?(Array)
        operators = config[:operators]
        default_operator = config[:default_operator]
        escape_token = config[:escape_token] || '`'
        escaped_value = config[:escaped_value] || lambda { |s| s }

        representation_of = lambda do |something|
          if operators.has_key?(something)
            something.to_sym
          elsif something.is_a?(Symbol) || something.is_a?(String)
            something
          else
            error("#{something} is neither an operator nor a value")
          end
        end

        type_of = lambda { |symbol| operators.has_key?(symbol) ? operators[symbol][:type] : 'value' }

        is_infix = lambda { |symbol| type_of[symbol]== 'infix' }
        is_prefix = lambda { |symbol| type_of[symbol]== 'prefix' }
        is_postfix = lambda { |symbol| type_of[symbol]== 'postfix' }
        is_combinator = lambda { |symbol| is_infix[symbol] || is_prefix[symbol] || is_postfix[symbol] }
        is_escape = lambda { |symbol| symbol == escape_token }
        awaits_value = lambda { |symbol| is_infix[symbol] || is_prefix[symbol] }

        operator_stack = []
        rpn = []
        awaiting_value = true

        while input.length > 0 do
          token = input.shift
          error("All tokens should be strings, but #{token.inspect} is not") unless token.is_a? String

          if is_escape[token]
            if input.empty?
              error('Escape token #{escape_token} has no following token')
            else
              value_token = input.shift

              if awaiting_value
                # push the escaped value of the token

                rpn.push(escaped_value[value_token])
              else
                # value catenation

                input.unshift(value_token)
                input.unshift(escape_token)
                input.unshift(default_operator)
              end
              awaiting_value = false
            end
          elsif token == '(' && awaiting_value
            # opening parenthesis case, going to build
            # a value
            operator_stack.push(token)
            awaiting_value = true
          elsif token == '('
            # value catenation

            input.unshift(token)
            input.unshift(default_operator)
            awaiting_value = false
          elsif token == ')'
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
          elsif is_prefix[token]
            if awaiting_value
              precedence = operators[token][:precedence]

              # pop higher-precedence operators off the operator stack
              while is_combinator[token] && operator_stack.length > 0 && operator_stack.last != '(' do
                opPrecedence = operators[operator_stack.last][:precedence]

                if precedence < opPrecedence
                  op = operator_stack.pop

                  rpn.push(representation_of[op])
                else
                  break
                end
              end

              operator_stack.push(token)
              awaiting_value = awaits_value[token]
            else
              # value catenation

              input.unshift(token)
              input.unshift(default_operator)
              awaiting_value = false
            end
          elsif is_combinator[token]
            precedence = operators[token][:precedence]

            # pop higher-precedence operators off the operator stack
            while is_combinator[token] && operator_stack.length > 0 && operator_stack.last != '(' do
              opPrecedence = operators[operator_stack.last][:precedence]

              if precedence < opPrecedence
                op = operator_stack.pop

                rpn.push(representation_of[op])
              else
                break
              end
            end

            operator_stack.push(token)
            awaiting_value = awaits_value[token]
          elsif awaiting_value
            # as expected, go straight to the output

            rpn.push(representation_of[token])
            awaiting_value = false
          else
            # value catenation

            input.unshift(token)
            input.unshift(default_operator)
            awaiting_value = false
          end
        end

        # pop remaining symbols off the stack and push them
        while operator_stack.length > 0 do
          op = operator_stack.pop

          if operators.has_key?(op.to_s)
            rpn.push(representation_of[op])
          else
            error("Don't know how to push operator #{op}")
          end
        end

        rpn
      else
        error("Don't know how to compile #{input.inspect}")
      end
    end

    def run (config, input)
      if input.is_a?(String)
        run(config, compile(config, lex(config, input)))
      elsif !input.is_a?(Array)
        error("Don't know how to run #{input.inspect}")
      elsif input.length > 1 && input.none? { |element| element.is_a? Symbol }
        run(config, compile(config, input))
      else
        operators = config[:operators]
        to_value = config[:to_value]

        lambdas = Hash.new do |hash, symbol|
          hash[symbol] = operators[symbol.to_s][:lda]
        end

        stack = []

        input.each do |element|
          if element.is_a?(String)
            stack.push(to_value[element])
          elsif element.is_a?(Symbol) && operators.has_key?(element.to_s)
            lda = lambdas[element]
            arity = lda.arity

            if stack.length < arity
              error("Not enough values on the stack to use #{element.inspect}")
            else
              indexed_parameters = []

              arity.times do
                indexed_parameters.unshift(stack.pop())
              end

              stack.push(lda.call(*indexed_parameters))
            end
          else
            error("Don't know what to do with #{element.inspect}")
          end
        end

        if stack.empty?
          nil
        elsif stack.length > 1
          error("should only be one value to return, but there were #{stack.length} values on the stack: #{stack.inspect}")
        else
          stack.first
        end
      end
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
      if str.empty?
        []
      elsif str.start_with?(character)
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

  module Example
    ARITHMETIC = {
      operators: {
        '+' => {
          type: 'infix',
          precedence: 1,
          lda: lambda { |a, b| a + b }
        },
        '-' => {
          type: 'infix',
          precedence: 1,
          lda: lambda { |a, b| a - b }
        },
        '*' => {
          type: 'infix',
          precedence: 3,
          lda: lambda { |a, b| a * b }
        },
        '/' => {
          type: 'infix',
          precedence: 2,
          lda: lambda { |a, b| a / b }
        },
        '!' => {
          type: 'postfix',
          precedence: 4,
          lda: lambda { |n| (1..n).reduce(&:*) }
        }
      },
      default_operator: '*',
      to_value: lambda { |n| +(n.to_i) }
    }
  end

end

ShuntingYard.run(ShuntingYard::Example::ARITHMETIC, '3! + 4*5')
