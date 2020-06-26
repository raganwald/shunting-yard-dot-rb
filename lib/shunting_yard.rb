# coding: utf-8

require 'set'

module ShuntingYard

  class << self

    # takes as input raw text, returns an array of symbols
    # config.operators is a dictionary, with each key being an operator
    # this version only supports single-character operators
    def lex(config, input)
      error(config, "Don't know how to lex #{input.inspect}") unless input.is_a?(String)

      # operators that automatically break symbols apart
      # TODO: sort by descending order of length for the
      # purpose of disambiguating the && operator from &,
      # if we ever want that
      breaking_operators = config[:operators].keys.select { |key| key.match(/^[a-zA-Z]/).nil? }.map(&:to_s)
      parentheses = ['(', ')']
      significant_chunks = breaking_operators.concat(parentheses)

      # split on whitespace
      # TODO: make whitespace breaking configurable?
      # seems unlikely
      strings = input.split /\s+/

      split_strings_on_significant_chunks(strings, significant_chunks)
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
            error(config, "#{something} is neither an operator nor a value")
          end
        end

        type_of = lambda { |symbol| operators.has_key?(symbol) ? operators[symbol][:type] : 'value' }
        type_of = lambda { |symbol| operators.has_key?(symbol) ? operators[symbol][:type] : 'value' }

        is_infix = lambda { |symbol| type_of[symbol]== 'infix' }
        is_prefix = lambda { |symbol| type_of[symbol]== 'prefix' }
        is_postfix = lambda { |symbol| type_of[symbol]== 'postfix' }
        is_nullary = lambda { |symbol| type_of[symbol]== 'none' }
        is_combinator = lambda { |symbol| is_infix[symbol] || is_prefix[symbol] || is_postfix[symbol] || is_nullary[symbol] }
        is_escape = lambda { |symbol| symbol == escape_token }
        awaits_value = lambda { |symbol| is_infix[symbol] || is_prefix[symbol] }

        operator_stack = []
        rpn = []
        awaiting_value = true

        while input.length > 0 do
          token = input.shift
          error(config, "All tokens should be strings, but #{token.inspect} is not") unless token.is_a? String

          if is_escape[token]
            if input.empty?
              error(config, 'Escape token #{escape_token} has no following token')
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
            input.unshift(default_operator) if default_operator
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
              error(config, 'Unbalanced parentheses')
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
              input.unshift(default_operator) if default_operator
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
            rpn.push(representation_of[token])
            puts "awaiting value, #{token} -> #{representation_of[token].inspect} -> #{rpn.inspect}"
            awaiting_value = false
          elsif default_operator
            puts "value catenation, unshifting #{token.inspect} #{default_operator.inspect}"
            input.unshift(token)
            input.unshift(default_operator)
            awaiting_value = false
          else
            puts "Unexpected appearance of #{token.inspect}, not awaiting a value"
            error(config, "Unexpected appearance of #{token}, not awaiting a value")
          end
        end

        # pop remaining symbols off the stack and push them
        while operator_stack.length > 0 do
          op = operator_stack.pop

          if operators.has_key?(op.to_s)
            rpn.push(representation_of[op])
          else
            error(config, "Don't know how to push operator #{op}")
          end
        end

        rpn
      else
        error(config, "Don't know how to compile #{input.inspect}")
      end
    end

    def run (config, input)
      if input.is_a?(String)
        run(config, compile(config, lex(config, input)))
      elsif !input.is_a?(Array)
        error(config, "Don't know how to run #{input.inspect}")
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
              error(config, "Not enough values on the stack to use #{element.inspect}")
            else
              indexed_parameters = []

              arity.times do
                indexed_parameters.unshift(stack.pop())
              end

              stack.push(lda.call(*indexed_parameters))
            end
          else
            error(config, "Don't know what to do with #{element.inspect}")
          end
        end

        if stack.empty?
          nil
        elsif stack.length > 1
          error(config, "should only be one value to return, but there were #{stack.length} values on the stack: #{stack.inspect}")
        else
          stack.first
        end
      end
    end

    private

    def error(config, message)
      error_class = config[:error_class] || RuntimeError
      raise error_class.new(message)
    end

    def split_strings_on_significant_chunks(strings, chunks = [])
      if chunks.empty?
        strings
      else
        chunk = chunks.first
        split_strings_on_significant_chunks(
          strings.flat_map { |str| split_on_a_significant_chunk(str, chunk) },
          chunks[1..-1]
        )
      end
    end

    # split each string around significant chunks,
    # but keep the chunks
    def split_on_a_significant_chunk(str, chunk)
      if str.empty?
        []
      elsif str.start_with?(chunk)
        [chunk].concat(split_on_a_significant_chunk(str[chunk.size..-1], chunk))
      elsif str.end_with?(chunk)
        split_on_a_significant_chunk(str[0..-(chunk.size + 1)], chunk).concat([chunk])
      else
        substrings = str.split(chunk)
        first = substrings.first
        rest = substrings[1..-1].flat_map { |substrings| [chunk, substrings] }
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
      to_value: lambda { |token| +(token.to_i) }
    }

    # Compiles a memebership test lambda
    # A membership test lambda is of the form lambda { |*args| boolean }
    # We compose them via composer lambdas. The binary
    # lambda composer is lambda { |boolean, boolean| boolean }

    THUNK_INTERSECTION = lambda { |a, b| a[] && b[] }
    THUNK_UNION = lambda { |a, b| a[] || b[] }

    def self.binary_membership(thunk_composer)
      lambda do |test1, test2|
        lambda { |*args| thunk_composer[ lambda { test1[*args] }, lambda { test2[*args] }] }
      end
    end

    FLAGS = {
      operators: {
        'and' => {
          type: 'infix',
          precedence: 1,
          lda: binary_membership(THUNK_INTERSECTION)
        },
        'or' => {
          type: 'infix',
          precedence: 1,
          lda: binary_membership(THUNK_UNION)
        },
        '∩' => {
          type: 'infix',
          precedence: 3,
          lda: binary_membership(THUNK_INTERSECTION)
        },
        '∪' => {
          type: 'infix',
          precedence: 3,
          lda: binary_membership(THUNK_UNION)
        }
      },
      to_value: lambda { |token| lambda { |flags = {}| flags && !!flags[token.to_sym] } }
    }

    flag_test = ShuntingYard.run(ShuntingYard::Example::FLAGS, 'tall ∩ thin ∩ goodlooking')
    puts flag_test[tall: true, thin: true, goodlooking: true]

    flag_test2 = ShuntingYard.run(ShuntingYard::Example::FLAGS, 'tall or thin or poor')
    puts flag_test2[tall: false, thin: false, poor: false]
    puts flag_test2[tall: true, thin: false, poor: false]
    puts flag_test2[tall: false, thin: true, poor: false]
    puts flag_test2[tall: false, thin: false, poor: true]
    puts flag_test2[tall: true, thin: true, poor: true]

    # also a membership test, but we now have paramaterized membership tests, not just
    # the magic of to_value

    NUMBERS = {
      operators: {
        '∩' => {
          type: 'infix',
          precedence: 1,
          lda: binary_membership(THUNK_INTERSECTION)
        },
        '∪' => {
          type: 'infix',
          precedence: 1,
          lda: binary_membership(THUNK_UNION)
        },
        '<' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |comparator| lambda { |number| number < comparator } }
        },
        '>' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |comparator| lambda { |number| number > comparator } }
        },
        '==' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |comparator| lambda { |number| number == comparator } }
        },
        '%' => {
          type: 'infix',
          precedence: 2,
          lda: lambda { |remainder, modulus | lambda { |number| number % modulus == remainder % modulus } }
        },
      },
      to_value: lambda { |token| token.to_i }
    }

    number_test = ShuntingYard.run(ShuntingYard::Example::NUMBERS, '>2 ∩ < 5 ∩ 0 % 2')
    puts number_test[3].inspect
    puts number_test[4].inspect
    puts ({ '1': number_test[1], '2': number_test[2], '3': number_test[3], '4': number_test[4], '5': number_test[5], '6': number_test[6] })

    # a technique for creating unary keyword functions
    # this version uses an infix operator
    # another technique might be creating functions as first-class objects
    # and figuring out how to perform "apply"

    KEYWORDS = {
      operators: {
        '∩' => {
          type: 'infix',
          precedence: 2,
          lda: binary_membership(THUNK_INTERSECTION)
        },
        '∪' => {
          type: 'infix',
          precedence: 2,
          lda: binary_membership(THUNK_UNION)
        },
        'account:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |token| lambda { |properties = {}| properties[:account].to_s == token.to_s } }
        },
        'user:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |token| lambda { |properties = {}| properties[:user].to_s == token.to_s } }
        },
        'service:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |token| lambda { |properties = {}| properties[:service].to_s == token.to_s } }
        },
        'allow' => {
          type: 'none',
          precedence: 4,
          lda: lambda { lambda { |properties = {}| true } }
        },
        'disallow' => {
          type: 'none',
          precedence: 4,
          lda: lambda { lambda { |properties = {}| false } }
        },
      },
      to_value: lambda do |token|
         token.to_s
      end
    }

    puts 'keywords:'
    keywords_test = ShuntingYard.run(ShuntingYard::Example::KEYWORDS, 'account: 1')
    puts keywords_test[{account: 1}].inspect
    puts keywords_test[{account: 2}].inspect
    puts keywords_test[{account: 3}].inspect

    puts 'keywords2:'
    keywords_test2 = ShuntingYard.run(ShuntingYard::Example::KEYWORDS, 'allow')
    puts keywords_test2[{account: 1}].inspect
    puts keywords_test2[{account: 2}].inspect
    puts keywords_test2[{account: 3}].inspect

    puts 'binaries:'
    keywords_test3 = ShuntingYard.run(ShuntingYard::Example::KEYWORDS, 'disallow ∩ disallow')
    puts keywords_test3[{}].inspect

    class TestError < StandardError; end

    NO_ERROR_CLASS = {
      operators: {
        'catenate' => {
          type: 'infix',
          precedence: 1,
          lda: lambda { |a, b| "#{a} #{b}"}
        }
      },
      to_value: lambda { |token| token.to_s }
    }

    begin
      ShuntingYard.run(ShuntingYard::Example::NO_ERROR_CLASS, 'A catenate')
    rescue TestError
      puts "incorrectly raised a test error"
    rescue RuntimeError
      puts "correctly raised a runtime error"
    end

    class TestError; end

    WITH_ERROR_CLASS = {
      operators: {
        'catenate' => {
          type: 'infix',
          precedence: 1,
          lda: lambda { |a, b| "#{a} #{b}"}
        }
      },
      to_value: lambda { |token| token.to_s },
      error_class: TestError
    }

    begin
      ShuntingYard.run(ShuntingYard::Example::WITH_ERROR_CLASS, 'A catenate')
    rescue TestError
      puts "correctly raised a test error"
    rescue RuntimeError
      puts "incorrectly raised a runtime error"
    end

    begin
      ShuntingYard.compile(ShuntingYard::Example::WITH_ERROR_CLASS, 'A B')
    rescue TestError
      puts "correctly raised a test error"
    rescue RuntimeError
      puts "incorrectly raised a runtime error"
    end

    class ExpressionError < StandardError; end

    EXPRESSION_LANGUAGE = {
      operators: {
        'and' => {
          type: 'infix',
          precedence: 1,
          lda: binary_membership(lambda { |a, b| a[] && b[] })
        },
        'or' => {
          type: 'infix',
          precedence: 1,
          lda: binary_membership(lambda { |a, b| a[] || b[] })
        },
        '&&' => {
          type: 'infix',
          precedence: 2,
          lda: binary_membership(lambda { |a, b| a[] && b[] })
        },
        '||' => {
          type: 'infix',
          precedence: 2,
          lda: binary_membership(lambda { |a, b| a[] || b[] })
        },
        'account_feature:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda do |feature_name|
            # TODO: check for the existence of the feature at compile time
            lambda do |account, user, service_id = nil|
              account.account_features.any? { |feature| feature.feature_name == feature_name.to_sym }
            end
          end
        },
        'toggle:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda do |toggle_name|
            # TODO: check for the existence of the toggle at compile time
            lambda { |account, user, service_id = nil| TOGGLE_CLASS[toggle_name].active?(account, user, service_id) }
          end
        },
        'subdomain:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |subdomain| lambda { |account, user, service_id = nil| account.subdomain == subdomain } }
        },
        'account_id:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |account_id| lambda { |account, user, service_id = nil| account.id.to_s == account_id } }
        },
        'user_id:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |user_id| lambda { |account, user, service_id = nil| user.id.to_s == user_id } }
        },
        'service_id:' => {
          type: 'prefix',
          precedence: 4,
          lda: lambda { |service_id| lambda { |account, user, service_id = nil| service_id && (service_id.to_s == service_id) } }
        },
        'allow' => {
          type: 'none',
          precedence: 4,
          lda: lambda { lambda { |account, user, service_id = nil| true } }
        },
        'disallow' => {
          type: 'none',
          precedence: 4,
          lda: lambda { lambda { |account, user, service_id = nil| false } }
        },
      },
      to_value: lambda { |token| token.to_s },
      error_class: ExpressionError
    }

    ShuntingYard.lex(ShuntingYard::Example::EXPRESSION_LANGUAGE, 'disallow && disallow')

    MARKDOWN_CONFIG = {
      operators: {
        'catenate' => {
          type: 'infix',
          precedence: 1,
          lda: lambda { |a, b| "#{a} #{b}"}
        },
        '_' => {
          type: 'prefix',
          precedence: 2,
          lda: lambda { |a| "_#{a}_"}
        },
        '**' => {
          type: 'prefix',
          precedence: 2,
          lda: lambda { |a| "**#{a}**"}
        }
      },
      to_value: lambda { |token| token.to_s }
    }

    puts 'herewego'

    begin
      ShuntingYard.run(ShuntingYard::Example::MARKDOWN_CONFIG, 'hello world')
    rescue TestError
      puts "raised a test error"
    rescue RuntimeError
      puts "raised a runtime error"
    end

    begin
      ShuntingYard.run(ShuntingYard::Example::MARKDOWN_CONFIG, 'hello _world')
    rescue TestError
      puts "raised a test error"
    rescue RuntimeError
      puts "raised a runtime error"
    end

  end

end


