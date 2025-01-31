require_dependency 'issue_template_description'

class IssueTemplate < ActiveRecord::Base
  include Redmine::SafeAttributes

  acts_as_customizable

  belongs_to :project
  belongs_to :tracker
  belongs_to :status, :class_name => 'IssueStatus', :foreign_key => 'status_id'
  belongs_to :author, :class_name => 'User', :foreign_key => 'author_id'
  belongs_to :assigned_to, :class_name => 'Principal', :foreign_key => 'assigned_to_id'
  belongs_to :fixed_version, :class_name => 'Version', :foreign_key => 'fixed_version_id'
  belongs_to :priority, :class_name => 'IssuePriority', :foreign_key => 'priority_id'
  belongs_to :category, :class_name => 'IssueCategory', :foreign_key => 'category_id'

  has_many :issues

  has_many :descriptions, -> { order(:position) }, :class_name => "IssueTemplateDescription", :dependent => :destroy
  accepts_nested_attributes_for :descriptions, :reject_if => :description_is_empty?, :allow_destroy => true

  has_many :section_groups, -> { order(:position) }, :class_name => 'IssueTemplateSectionGroup', :dependent => :destroy
  accepts_nested_attributes_for :section_groups, :reject_if => :section_group_is_empty?, :allow_destroy => true
  has_many :sections, :through => :section_groups

  has_many :issue_template_projects, dependent: :destroy
  has_many :template_projects, through: :issue_template_projects, source: :project

  if Redmine::Plugin.installed?(:redmine_multiprojects_issue)
    has_and_belongs_to_many :secondary_projects, class_name: 'Project', join_table: 'multiprojects_issue_templates'
  end

  validates_presence_of :template_title, :tracker, :author, :status, :template_projects
  validates_length_of :subject, :maximum => 255
  # validates_inclusion_of :done_ratio, :in => 0..100

  validates :estimated_hours, :numericality => { :greater_than_or_equal_to => 0, :allow_nil => true, :message => :invalid }
  validates :start_date, :date => true
  validates :due_date, :date => true
  # validate :validate_issue, :validate_required_fields

  scope :displayed_on_overview, -> { active.where(show_on_overview: true) }
  scope :active, -> { where(template_enabled: true) }

  safe_attributes :template_project_ids,
                  :secondary_project_ids,
                  :project_id,
                  :tracker_id,
                  :subject,
                  :description,
                  :template_title,
                  :template_description,
                  :template_image,
                  :template_enabled,
                  :show_on_overview,
                  :hide_file_attachment,
                  :is_private,
                  :status_id,
                  :category_id,
                  :assigned_to_id,
                  :priority_id,
                  :fixed_version_id,
                  :start_date,
                  :due_date,
                  :done_ratio,
                  :estimated_hours,
                  :custom_field_values,
                  :custom_fields,
                  :usage,
                  :authorized_viewers,
                  :custom_form,
                  :custom_form_path,
                  :tracker_read_only,
                  :descriptions_attributes,
                  :section_groups_attributes,
                  :split_description,
                  :typology_id,
                  :autocomplete_subject

  def to_s
    template_title
  end

  def validate_custom_field_values
    # Skip custom values validation when saving templates
  end

  def title_with_tracker
    if template_title == tracker.name
      "[#{tracker}]"
    else
      "[#{tracker}] #{template_title}"
    end
  end

  def has_been_deleted?
    IssueTemplate.where(id: self.id).blank?
  end

  def allowed_target_projects
    Project.active
  end

  def disabled_projects
    Project.all - Project.includes(:enabled_modules).where("enabled_modules.name" => :issue_templates)
  end

  def assignable_users
    if template_projects.any?
      users = template_projects.map(&:assignable_users).flatten.uniq
    else
      users = []
    end
    users << author if author
    users << assigned_to if assigned_to
    users.uniq.sort
  end

  # Overrides Redmine::Acts::Customizable::InstanceMethods#available_custom_fields
  def available_custom_fields
    available_custom_fields = []
    template_projects.each do |project|
      available_custom_fields |= project.all_issue_custom_fields.to_a
    end
    available_custom_fields |= tracker.custom_fields.all.to_a if tracker.present?
    available_custom_fields
  end

  # Returns the custom_field_values that can be edited by the given user
  def editable_custom_field_values(user = nil)
    custom_field_values.reject do |value|
      read_only_attribute_names(user).include?(value.custom_field_id.to_s)
    end
  end

  # Returns the names of attributes that are read-only for user or the current user
  # For users with multiple roles, the read-only fields are the intersection of
  # read-only fields of each role
  # The result is an array of strings where sustom fields are represented with their ids
  def read_only_attribute_names(user = nil)
    workflow_rule_by_attribute(user).reject { |attr, rule| rule != 'readonly' }.keys
  end

  # Returns a hash of the workflow rule by attribute for the given user # TODO : Cleanup these methods
  def workflow_rule_by_attribute(user = nil)
    return @workflow_rule_by_attribute if @workflow_rule_by_attribute && user.nil?

    user_real = user || User.current
    roles = user_real.admin ? Role.all : user_real.roles_for_project(project)
    return {} if roles.empty?

    result = {}
    workflow_permissions = WorkflowPermission.where(:tracker_id => tracker_id, :old_status_id => status_id, :role_id => roles.map(&:id)).all
    if workflow_permissions.any?
      workflow_rules = workflow_permissions.inject({}) do |h, wp|
        h[wp.field_name] ||= []
        h[wp.field_name] << wp.rule
        h
      end
      workflow_rules.each do |attr, rules|
        next if rules.size < roles.size
        uniq_rules = rules.uniq
        if uniq_rules.size == 1
          result[attr] = uniq_rules.first
        else
          result[attr] = 'required'
        end
      end
    end
    @workflow_rule_by_attribute = result if user.nil?
    result
  end

  def authorized_viewer_ids
    "#{authorized_viewers}".split('|').reject(&:blank?).map(&:to_i)
  end

  def assigned_to_function_id
    nil # TODO Make templates compatible with this functionality
  end

  def description_is_empty?(attributes)
    persisted = attributes["id"].present?
    case attributes["type"]
    when IssueTemplateDescriptionInstruction.name
      empty = attributes["text"].blank?
    end
    return (!persisted && empty)
  end

  def section_group_is_empty?(attributes)
    persisted = attributes["id"].present?
    has_no_title = attributes["title"].blank?
    has_no_sections = attributes["sections_attributes"].nil? || attributes["sections_attributes"].reject { |id, section| id == "$id_section$" }.blank?
    return (!persisted && has_no_title && has_no_sections)
  end

  def safe_attribute_names(user = nil)
    names = super
    names -= disabled_core_fields
    names
  end

  def disabled_core_fields
    tracker ? tracker.disabled_core_fields : []
  end

end
