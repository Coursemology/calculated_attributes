module CalculatedAttributes
  def calculated(*args)
    @config ||= CalculatedAttributes::Config.new
    @config.calculated(args.first, args.last) if args.size == 2
    @config
  end

  class CalculatedAttributes
    class Config
      def calculated(title = nil, lambda = nil)
        @calculations ||= {}
        @calculations[title] ||= lambda if title && lambda
        @calculations
      end
    end
  end
end
ActiveRecord::Base.extend CalculatedAttributes

ActiveRecord::Base.send(:include, Module.new do
  def calculated(*args)
    if self.class.respond_to? :scoped
      self.class.scoped.calculated(*args).find(id)
    else
      self.class.all.calculated(*args).find(id)
    end
  end

  def method_missing(sym, *args, &block)
    no_sym_in_attr =
      if @attributes.respond_to? :include?
        !@attributes.include?(sym.to_s)
      else
        !@attributes.key?(sym.to_s)
      end
    if no_sym_in_attr && (self.class.calculated.calculated[sym] || self.class.base_class.calculated.calculated[sym])
      Rails.logger.warn("Using calculated value without including it in the relation: #{sym}") if defined? Rails
      class_with_attr =
        if self.class.calculated.calculated[sym]
          self.class
        else
          self.class.base_class
        end
      if class_with_attr.respond_to? :scoped
        class_with_attr.scoped.calculated(sym).find(id).send(sym)
      else
        class_with_attr.all.calculated(sym).find(id).send(sym)
      end
    else
      super(sym, *args, &block)
    end
  end

  def respond_to?(method, include_private = false)
    no_sym_in_attr =
      if @attributes.respond_to? :include?
        !@attributes.include?(method.to_s)
      elsif @attributes.respond_to? :key?
        !@attributes.key?(method.to_s)
      else
        true
      end
    super || (no_sym_in_attr && (self.class.calculated.calculated[method] || self.class.base_class.calculated.calculated[method]))
  end
end)

ActiveRecord::Relation.send(:include, Module.new do
  def calculated(*args)
    projections = arel.projections
    args.each do |arg|
      lam = klass.calculated.calculated[arg] || klass.base_class.calculated.calculated[arg]
      sql = lam.call
      new_projection = sql.is_a?(String) ? Arel.sql("(#{sql})").as(arg.to_s) : sql.as(arg.to_s)
      new_projection.calculated_attr!
      projections.push new_projection
    end
    select(projections)
  end
end)