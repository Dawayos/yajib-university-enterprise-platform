import { safeText, validUuid } from "./security.js";

export class PlatformService {
  constructor(supabase) { this.db = supabase; }

  async dashboardSummary() {
    const { data, error } = await this.db.rpc("get_dashboard_summary");
    if (error) throw error;
    return data || {};
  }

  async recentActivity(limit = 8) {
    const { data, error } = await this.db.from("audit_logs").select("action,entity_type,created_at").order("created_at", { ascending:false }).limit(Math.min(Math.max(limit, 1), 20));
    if (error) throw error;
    return data || [];
  }

  async list(module, { limit = 25 } = {}) {
    const map = {
      examinations: { table:"exams", columns:"id,title,status,starts_at,ends_at,courses(code,title)", order:"created_at" },
      results: { table:"results", columns:"id,total_score,letter_grade,status,published_at,courses(code,title),profiles!results_student_id_fkey(full_name,student_number)", order:"updated_at" },
      learning: { table:"learning_modules", columns:"id,title,module_order,is_published,created_at,courses(code,title)", order:"created_at" },
      assignments: { table:"assignments", columns:"id,title,due_at,max_score,status,courses(code,title)", order:"created_at" },
      research: { table:"research_projects", columns:"id,title,status,research_type,submitted_at,updated_at", order:"updated_at" },
      records: { table:"enrollments", columns:"id,status,created_at,courses(code,title,credit_units),academic_sessions(name)", order:"created_at" },
      transcripts: { table:"transcript_requests", columns:"id,reference_number,status,purpose,created_at,processed_at", order:"created_at" },
      users: { table:"profiles", columns:"id,full_name,email,student_number,staff_number,is_active,created_at", order:"created_at" },
      courses: { table:"courses", columns:"id,code,title,credit_units,level,is_active,departments(name)", order:"code" },
      approvals: { table:"result_approvals", columns:"id,stage,decision,comment,decided_at,results(id,letter_grade,courses(code))", order:"created_at" },
      audit: { table:"audit_logs", columns:"id,action,entity_type,entity_id,created_at,ip_address", order:"created_at" }
    };
    const cfg = map[module];
    if (!cfg) throw new Error("UNKNOWN_MODULE");
    const { data, error } = await this.db.from(cfg.table).select(cfg.columns).order(cfg.order, { ascending:false }).limit(Math.min(Math.max(limit,1),100));
    if (error) throw error;
    return data || [];
  }

  async createExam(input) {
    if (!validUuid(input.course_id)) throw new Error("INVALID_COURSE");
    const title = safeText(input.title, 160);
    if (title.length < 5) throw new Error("INVALID_TITLE");
    const startsAt = new Date(input.starts_at);
    const endsAt = new Date(input.ends_at);
    if (!Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsAt.getTime()) || endsAt <= startsAt) throw new Error("INVALID_DATE_RANGE");
    const { data, error } = await this.db.from("exams").insert({ course_id:input.course_id, title, instructions:safeText(input.instructions,4000), starts_at:startsAt.toISOString(), ends_at:endsAt.toISOString(), duration_minutes:Number(input.duration_minutes), status:"draft" }).select().single();
    if (error) throw error;
    return data;
  }

  async createLearningModule(input) {
    if (!validUuid(input.course_id)) throw new Error("INVALID_COURSE");
    const title = safeText(input.title,160), content = safeText(input.content,10000);
    if (title.length < 3 || content.length < 10) throw new Error("INVALID_CONTENT");
    const { data, error } = await this.db.from("learning_modules").insert({ course_id:input.course_id,title,content,module_order:Number(input.module_order)||1,is_published:false }).select().single();
    if (error) throw error; return data;
  }

  async createResearchProject(input) {
    const title=safeText(input.title,220), abstract=safeText(input.abstract,5000);
    if(title.length<10||abstract.length<50)throw new Error("INVALID_RESEARCH");
    const {data,error}=await this.db.from("research_projects").insert({title,abstract,research_type:safeText(input.research_type,30),status:"draft"}).select().single();
    if(error)throw error; return data;
  }

  async myCourses() {
    const { data, error } = await this.db.from("courses").select("id,code,title").eq("is_active",true).order("code").limit(200);
    if(error)throw error; return data||[];
  }

  subscribe(table, callback) {
    return this.db.channel(`live-${table}-${crypto.randomUUID()}`).on("postgres_changes", {event:"*",schema:"public",table}, callback).subscribe();
  }
}
