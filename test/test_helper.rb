ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Remplace temporairement une méthode de classe/singleton par un bloc,
    # exécute le test, puis restaure l'originale.
    # Pourquoi : cette version de minitest n'embarque pas Minitest::Mock#stub,
    # on fournit donc un équivalent maison minimal pour simuler WebPush, etc.
    # receiver       : l'objet (classe ou module) portant la méthode
    # method_name    : le nom de la méthode à remplacer (symbole)
    # replacement    : un lambda/proc qui remplace la méthode pendant le test
    # &block         : le corps du test, exécuté avec la méthode remplacée
    def stub_method(receiver, method_name, replacement)
      # On mémorise la méthode d'origine pour pouvoir la rétablir ensuite
      original = receiver.method(method_name)
      # On redéfinit la méthode sur le singleton du receiver (méthode de classe)
      receiver.singleton_class.send(:define_method, method_name, &replacement)
      # On exécute le corps du test avec la méthode remplacée
      yield
    ensure
      # Quoi qu'il arrive, on restaure la méthode d'origine
      receiver.singleton_class.send(:define_method, method_name, original)
    end
  end
end
