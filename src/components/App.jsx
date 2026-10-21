import { useState, useEffect, useCallback } from "react";
import { supabase } from "../lib/supabase.js";
import { useAuth } from "../context/AuthContext.jsx";

export default function App() {
  const { user, signOut } = useAuth();
  const [projects, setProjects] = useState([]);
  const [loadingProjects, setLoadingProjects] = useState(true);
  const [selectedProject, setSelectedProject] = useState(null);
  const [conversations, setConversations] = useState([]);
  const [newMessage, setNewMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [creatingProject, setCreatingProject] = useState(false);
  const [projectTitle, setProjectTitle] = useState("");
  const [projectDesc, setProjectDesc] = useState("");
  const [error, setError] = useState(null);

  const loadProjects = useCallback(async () => {
    setLoadingProjects(true);
    const { data, error: err } = await supabase
      .from("projects")
      .select("*")
      .order("created_at", { ascending: false });
    if (err) {
      setError(err.message);
    } else {
      setProjects(data || []);
    }
    setLoadingProjects(false);
  }, []);

  useEffect(() => {
    if (user) loadProjects();
  }, [user, loadProjects]);

  useEffect(() => {
    if (!selectedProject) {
      setConversations([]);
      return;
    }
    supabase
      .from("conversations")
      .select("*")
      .eq("project_id", selectedProject.id)
      .order("created_at", { ascending: true })
      .then(({ data, error: err }) => {
        if (err) setError(err.message);
        else setConversations(data || []);
      });
  }, [selectedProject]);

  async function handleCreateProject(e) {
    e.preventDefault();
    setSending(true);
    setError(null);
    const { data, error: err } = await supabase
      .from("projects")
      .insert({
        title: projectTitle || "Untitled project",
        description: projectDesc || null,
      })
      .select()
      .single();
    if (err) {
      setError(err.message);
    } else {
      setProjects((prev) => [data, ...prev]);
      setSelectedProject(data);
      setProjectTitle("");
      setProjectDesc("");
      setCreatingProject(false);
    }
    setSending(false);
  }

  async function handleSendMessage(e) {
    e.preventDefault();
    if (!newMessage.trim() || !selectedProject) return;
    setSending(true);
    setError(null);
    const msg = newMessage.trim();
    setNewMessage("");

    const { error: err } = await supabase.from("conversations").insert({
      project_id: selectedProject.id,
      role: "user",
      content: msg,
    });
    if (err) {
      setError(err.message);
      setNewMessage(msg);
    } else {
      setConversations((prev) => [
        ...prev,
        { id: crypto.randomUUID(), project_id: selectedProject.id, role: "user", content: msg, tokens: 0, created_at: new Date().toISOString() },
      ]);
    }
    setSending(false);
  }

  async function handleDeleteProject(id) {
    const { error: err } = await supabase.from("projects").delete().eq("id", id);
    if (err) {
      setError(err.message);
    } else {
      setProjects((prev) => prev.filter((p) => p.id !== id));
      if (selectedProject?.id === id) setSelectedProject(null);
    }
  }

  const formatDate = (iso) => new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="header-left">
          <div className="auth-logo small">
            <span className="logo-br">br</span>
            <span className="logo-ai">AI</span>
            <span className="logo-ny">ny</span>
          </div>
        </div>
        <div className="header-right">
          <span className="user-email">{user?.email}</span>
          <button className="btn-ghost" onClick={() => signOut()}>
            Sair
          </button>
        </div>
      </header>

      <div className="app-body">
        <aside className="sidebar">
          <button className="btn-primary sidebar-new" onClick={() => setCreatingProject((v) => !v)}>
            {creatingProject ? "Cancelar" : "+ Novo projeto"}
          </button>

          {creatingProject && (
            <form className="project-form" onSubmit={handleCreateProject}>
              <input
                type="text"
                placeholder="Título do projeto"
                value={projectTitle}
                onChange={(e) => setProjectTitle(e.target.value)}
                className="project-input"
              />
              <textarea
                placeholder="Descrição (opcional)"
                value={projectDesc}
                onChange={(e) => setProjectDesc(e.target.value)}
                rows={2}
                className="project-input"
              />
              <button type="submit" className="btn-primary" disabled={sending}>
                {sending ? "Criando..." : "Criar"}
              </button>
            </form>
          )}

          <div className="project-list">
            {loadingProjects && <p className="sidebar-empty">Carregando...</p>}
            {!loadingProjects && projects.length === 0 && (
              <p className="sidebar-empty">Nenhum projeto ainda. Crie o primeiro!</p>
            )}
            {projects.map((p) => (
              <div
                key={p.id}
                className={`project-item ${selectedProject?.id === p.id ? "active" : ""}`}
                onClick={() => setSelectedProject(p)}
              >
                <div className="project-item-info">
                  <span className="project-item-title">{p.title}</span>
                  <span className="project-item-date">{formatDate(p.created_at)}</span>
                </div>
                <button
                  className="project-item-delete"
                  onClick={(e) => { e.stopPropagation(); handleDeleteProject(p.id); }}
                  title="Excluir"
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        </aside>

        <main className="main-panel">
          {!selectedProject && (
            <div className="empty-state">
              <div className="empty-icon">◆</div>
              <h2>Selecione ou crie um projeto</h2>
              <p>Escolha um projeto na barra lateral ou crie um novo para começar a conversar com o brAIny.</p>
            </div>
          )}

          {selectedProject && (
            <>
              <div className="chat-header">
                <h2 className="chat-title">{selectedProject.title}</h2>
                {selectedProject.description && <p className="chat-desc">{selectedProject.description}</p>}
              </div>

              <div className="chat-messages">
                {conversations.length === 0 && (
                  <p className="chat-empty">Nenhuma mensagem ainda. Envie uma instrução para começar.</p>
                )}
                {conversations.map((c) => (
                  <div key={c.id} className={`message message-${c.role}`}>
                    <span className="message-role">{c.role === "user" ? "Você" : "brAIny"}</span>
                    <p className="message-content">{c.content}</p>
                  </div>
                ))}
              </div>

              <form className="composer" onSubmit={handleSendMessage}>
                <input
                  type="text"
                  placeholder="Descreva o que você quer criar..."
                  value={newMessage}
                  onChange={(e) => setNewMessage(e.target.value)}
                  disabled={sending}
                />
                <button type="submit" className="btn-primary" disabled={sending || !newMessage.trim()}>
                  {sending ? "..." : "Enviar"}
                </button>
              </form>
            </>
          )}
        </main>

        {selectedProject && (
          <aside className="preview-panel">
            <div className="preview-header">
              <span>Preview</span>
              <span className={`status-badge status-${selectedProject.status}`}>{selectedProject.status}</span>
            </div>
            <div className="preview-body">
              <div className="preview-placeholder">
                <p>O preview do projeto aparecerá aqui após a geração.</p>
              </div>
            </div>
          </aside>
        )}
      </div>

      {error && (
        <div className="error-toast" onClick={() => setError(null)}>
          {error}
        </div>
      )}
    </div>
  );
}
