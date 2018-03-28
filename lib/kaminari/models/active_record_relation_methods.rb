module Kaminari
  module ActiveRecordRelationMethods
    # a workaround for AR 3.0.x that returns 0 for #count when page > 1
    # if +limit_value+ is specified, load all the records and count them
    if ActiveRecord::VERSION::STRING < '3.1'
      def count(column_name = nil, options = {}) #:nodoc:
        limit_value && !options[:distinct] ? length : super(column_name, options)
      end
    end

    def entry_name
      model_name.human.downcase
    end

    def reset #:nodoc:
      @total_count = nil
      super
    end

    def total_count(column_name = :all, options = {}) #:nodoc:
      # #count overrides the #select which could include generated columns referenced in #order, so skip #order here, where it's irrelevant to the result anyway
      @total_count ||= begin
        c = except(:offset, :limit, :order)

        # Remove includes only if they are irrelevant
        c = c.except(:includes) unless references_eager_loaded_tables?

        # Rails 4.1 removes the `options` argument from AR::Relation#count
        args = [column_name]
        args << options if ActiveRecord::VERSION::STRING < '4.1.0'

        # .group returns an OrderdHash that responds to #count
        c = c.count(*args)
        if c.is_a?(Hash) || c.is_a?(ActiveSupport::OrderedHash)
          c.count
        else
          c.respond_to?(:count) ? c.count(*args) : c
        end
      end
    end

    def without_count
      extend ::Kaminari::PaginatableWithoutCount
    end
  end

  # A module that makes AR::Relation paginatable without having to cast another SELECT COUNT query
  module PaginatableWithoutCount
    # Overwrite AR::Relation#load to actually load one more record to judge if the page has next page
    # then store the result in @_has_next ivar
    def load
      if loaded? || limit_value.nil?
        super
      else
        @values[:limit] = limit_value + 1
        # FIXME: this could be removed when we're dropping AR 4 support
        @arel.limit = @values[:limit] if @arel && (Integer === @arel.limit)
        super
        @values[:limit] = limit_value - 1
        # FIXME: this could be removed when we're dropping AR 4 support
        @arel.limit = @values[:limit] if @arel && (Integer === @arel.limit)

        if @records.any?
          @records = @records.dup if (frozen = @records.frozen?)
          @_has_next = !!@records.delete_at(limit_value)
          @records.freeze if frozen
        end

        self
      end
    end

    # The page wouldn't be the last page if there's "limit + 1" record
    def last_page?
      !out_of_range? && !@_has_next
    end

    # Empty relation needs no pagination
    def out_of_range?
      load unless loaded?
      @records.empty?
    end

    # Force to raise an exception if #total_count is called explicitly.
    def total_count
      raise "This scope is marked as a non-count paginable scope and can't be used in combination " \
            "with `#paginate' or `#page_entries_info'. Use #link_to_next_page or #link_to_previous_page instead."
    end
  end
end
