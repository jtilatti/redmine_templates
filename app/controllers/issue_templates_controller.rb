class IssueTemplatesController < ApplicationController

  helper :custom_fields
  include CustomFieldsHelper
  helper :trackers
  include TrackersHelper

  before_action :authorize_global, except: [:add_repeatable_group]
  before_action :find_project, only: [:init]
  before_action :find_optional_project, only: [:index, :new, :edit]

  def init
    params[:issue].merge!({ project_id: params[:project_id] }) if params[:issue]
    @issue_template = IssueTemplate.new
    @issue_template.safe_attributes = params[:issue]
    @issue_template.project = @project
    @issue_template.template_projects = [@project]
    @issue_template.author ||= User.current
    @issue_template.template_title = @issue_template.subject
    if Redmine::Plugin.installed?(:redmine_multiprojects_issue)
      @issue_template.secondary_project_ids = params[:issue][:project_ids] if params[:issue]
    end

    @priorities = IssuePriority.active
    render :new
  end

  def new
    @issue_template = IssueTemplate.new(custom_form: false)
    @priorities = IssuePriority.active
    @issue_template.project = @project if @project.present?
  end

  def custom_form
    # Show requested custom form
    @priorities = IssuePriority.active
    @issue_template = IssueTemplate.new(custom_form: true, custom_form_path: params[:path], template_projects: [Project.active.first])
    render layout: false
  end

  def edit
    @issue_template = IssueTemplate.find(params[:id])
    @priorities = IssuePriority.active
  end

  def create
    @issue_template = IssueTemplate.new
    @issue_template.safe_attributes = params[:issue_template]
    @issue_template.author ||= User.current
    @issue_template.usage = 0

    if @issue_template.save
      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_issue_template_successfully_created)
          redirect_to edit_issue_template_path(@issue_template)
        }
      end
    else
      @priorities = IssuePriority.active

      respond_to do |format|
        format.html { render :action => :new }
      end
    end
  end

  def update
    @issue_template = IssueTemplate.find(params[:id])
    @issue_template.safe_attributes = params[:issue_template]
    if @issue_template.save
      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_issue_template_successfully_updated)
          redirect_to edit_issue_template_path(@issue_template)
        }
      end
    else
      @priorities = IssuePriority.active
      render action: :edit
    end

  end

  def index
    @templates = IssueTemplate.order("custom_form desc, tracker_id desc, usage desc").includes(:issues)
  end

  # Updates the template form when changing the project, status or tracker on template creation/update
  def update_form
    unless params[:issue_template][:id].blank?
      @issue_template = IssueTemplate.find(params[:issue_template][:id])
      @issue_template.safe_attributes = params[:issue_template]
    else
      @issue_template = IssueTemplate.new
      @issue_template.safe_attributes = params[:issue_template]
    end
    @priorities = IssuePriority.active
  end

  def destroy
    @issue_template = IssueTemplate.find(params[:id])
    @issue_template.destroy
    respond_to do |format|
      format.html {
        flash[:notice] = l(:notice_issue_template_successfully_deleted)
        redirect_to(:back)
      }
    end
  end

  def enable
    @issue_template = IssueTemplate.find(params[:id])
    @issue_template.template_enabled = !@issue_template.template_enabled?
    @issue_template.save
  end

  def similar_templates
    @new_template = IssueTemplate.new
    @new_template.safe_attributes = params[:issue_template]
    @templates = IssueTemplate.all
    @similar_templates = []
    #compare subjects
    @templates.each do |t|
      sims = []
      taux = 0
      sims << @new_template.subject.similar(t.subject)
      sims << (@new_template.tracker_id == t.tracker_id ? 100.0 : 0.0)
      sims << @new_template.description.similar(t.description) unless t.description.blank?
      sims.each do |sim|
        taux += sim
      end
      taux = taux / sims.size
      if taux > 61.0
        @similar_templates << { :id => t.id,
                                :subject => t.subject,
                                :description => t.description,
                                :tracker => t.tracker.try(:name),
                                :similarity => Integer(taux)
        }
      end
    end
    @similar_templates.sort! { |a, b| b[:similarity] <=> a[:similarity] }
    respond_to do |format|
      format.json {
        render json: @similar_templates.to_json
      }
    end
  end

  def add_repeatable_group
    @sections_group = IssueTemplateSectionGroup.find(params[:sectionsGroupId])
    render partial: "issues/sections/add_repeatable_group"
  end

  private

  def find_project
    begin
      @project ||= Project.find(params[:project_id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end

  def find_optional_project
    @project = Project.find(params[:project_id]) unless params[:project_id].blank?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

end
