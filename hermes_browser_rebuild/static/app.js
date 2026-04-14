const PREVIEW_INTERVAL_MS = 2500;
const PREVIEW_UPLOAD_DEBOUNCE_MS = 1800;
const AUDIO_BAR_COUNT = 20;

const state = {
  meetings: [],
  currentMeetingId: null,
  activeTab: 'overview',
  mediaRecorder: null,
  voiceRecorder: null,
  meetingEventSource: null,
  recordingMode: 'idle',
  liveChunks: [],
  voiceChunks: [],
  previewUploadChain: Promise.resolve(),
  isStoppingMeeting: false,
  previewSequence: 0,
  previewRenderedSequence: 0,
  recordingStartedAt: null,
  recordingTimerInterval: null,
  voiceTurnStartedAt: null,
  voiceMonitor: {
    context: null,
    analyser: null,
    source: null,
    dataArray: null,
    rafId: null,
    silenceStartedAt: null,
    detectedSpeech: false,
    stream: null,
  },
  audioVisualizer: {
    context: null,
    source: null,
    analyser: null,
    dataArray: null,
    rafId: null,
  },
};

const el = {
  meetingList: document.getElementById('meeting-list'),
  meetingCount: document.getElementById('meeting-count'),
  workspaceTitle: document.getElementById('workspace-title'),
  workspaceSubtitle: document.getElementById('workspace-subtitle'),
  secureContextBadge: document.getElementById('secure-context-badge'),
  meetingStatus: document.getElementById('meeting-status'),
  modelStatus: document.getElementById('model-status'),
  recordingState: document.getElementById('recording-state'),
  captureTimer: document.getElementById('capture-timer'),
  newMeetingButton: document.getElementById('new-meeting-button'),
  recordToggle: document.getElementById('record-toggle'),
  summarizeButton: document.getElementById('summarize-button'),
  captureFeedback: document.getElementById('capture-feedback'),
  qaFeedback: document.getElementById('qa-feedback'),
  livePreviewBox: document.getElementById('live-preview-box'),
  transcriptBox: document.getElementById('transcript-box'),
  rawTranscriptBox: document.getElementById('raw-transcript-box'),
  summaryBox: document.getElementById('summary-box'),
  questionInput: document.getElementById('question-input'),
  askButton: document.getElementById('ask-button'),
  voiceQuestionButton: document.getElementById('voice-question-button'),
  speakToggle: document.getElementById('speak-toggle'),
  handsfreeToggle: document.getElementById('handsfree-toggle'),
  answerText: document.getElementById('answer-text'),
  answerMeta: document.getElementById('answer-meta'),
  answerAudio: document.getElementById('answer-audio'),
  audioReactiveBars: document.getElementById('audio-reactive-bars'),
  sourcesList: document.getElementById('sources-list'),
  artifactLinks: document.getElementById('artifact-links'),
  artifactLog: document.getElementById('artifact-log'),
  overviewLivePreview: document.getElementById('overview-live-preview'),
  overviewSummary: document.getElementById('overview-summary'),
  overviewAnswer: document.getElementById('overview-answer'),
  conversationThread: document.getElementById('conversation-thread'),
  meetingItemTemplate: document.getElementById('meeting-item-template'),
  conversationItemTemplate: document.getElementById('conversation-item-template'),
  tabButtons: Array.from(document.querySelectorAll('.tab-button')),
  tabPanels: Array.from(document.querySelectorAll('.tab-panel')),
};

function setFeedback(node, message, kind = '') {
  node.textContent = message;
  node.className = `feedback ${kind}`.trim();
}

function currentMeeting() {
  return state.meetings.find((meeting) => meeting.id === state.currentMeetingId) || null;
}

function isHandsFreeEnabled() {
  return Boolean(el.handsfreeToggle?.checked);
}

function stopAnswerPlaybackForBargeIn() {
  if (!el.answerAudio.classList.contains('hidden') && !el.answerAudio.paused) {
    el.answerAudio.pause();
    el.answerAudio.currentTime = 0;
    stopAudioReactiveBars();
  }
}

function disconnectMeetingStream() {
  if (state.meetingEventSource) {
    state.meetingEventSource.close();
    state.meetingEventSource = null;
  }
}

function applyMeetingEvent(payload) {
  if (!payload?.meeting) return;
  renderMeetingDetail(payload.meeting);
  if (payload.event === 'preview' && payload.provider) {
    setFeedback(el.captureFeedback, `Streaming preview updated via ${payload.provider}.`, 'success');
  }
  if (payload.event === 'answer' && payload.answer_provider) {
    setFeedback(el.qaFeedback, `Answered via ${payload.answer_provider}. ${payload.answer_note || ''}`.trim(), 'success');
  }
}

function connectMeetingStream(meetingId) {
  disconnectMeetingStream();
  if (!meetingId || typeof EventSource === 'undefined') return;
  const source = new EventSource(`/api/meetings/${meetingId}/events`);
  ['snapshot', 'preview', 'transcript_finalized', 'voice_transcribed', 'answer'].forEach((eventName) => {
    source.addEventListener(eventName, (event) => {
      try {
        applyMeetingEvent(JSON.parse(event.data));
      } catch (error) {
        console.error('Failed to parse meeting event', error);
      }
    });
  });
  source.onerror = () => {
    console.warn('Meeting event stream disconnected');
  };
  state.meetingEventSource = source;
}

async function api(path, options = {}) {
  const response = await fetch(path, options);
  if (!response.ok) {
    const body = await response.text();
    throw new Error(body || `Request failed: ${response.status}`);
  }
  const contentType = response.headers.get('content-type') || '';
  if (contentType.includes('application/json')) {
    return response.json();
  }
  return response.text();
}

function switchTab(tab) {
  state.activeTab = tab;
  el.tabButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.tab === tab);
  });
  el.tabPanels.forEach((panel) => {
    const active = panel.id === `tab-${tab}`;
    panel.classList.toggle('active', active);
    panel.classList.toggle('hidden-pane', !active);
  });
}

function formatDuration(ms) {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`;
}

function startRecordingTimer() {
  clearRecordingTimer();
  state.recordingStartedAt = Date.now();
  el.captureTimer.textContent = '00:00';
  state.recordingTimerInterval = window.setInterval(() => {
    if (!state.recordingStartedAt) return;
    const elapsed = Date.now() - state.recordingStartedAt;
    const text = formatDuration(elapsed);
    el.captureTimer.textContent = text;
    el.recordingState.textContent = `Recording ${text}`;
  }, 500);
}

function clearRecordingTimer() {
  if (state.recordingTimerInterval) {
    window.clearInterval(state.recordingTimerInterval);
    state.recordingTimerInterval = null;
  }
  state.recordingStartedAt = null;
  el.captureTimer.textContent = '00:00';
}

function renderSecureContext() {
  if (window.isSecureContext) {
    el.secureContextBadge.textContent = 'Secure context ready';
    el.secureContextBadge.style.borderColor = 'rgba(16, 185, 129, 0.35)';
    el.secureContextBadge.style.color = '#a7f3d0';
    return;
  }
  el.secureContextBadge.textContent = 'Use Tailscale HTTPS for mic access';
  el.secureContextBadge.style.borderColor = 'rgba(239, 68, 68, 0.35)';
  el.secureContextBadge.style.color = '#fecaca';
}

function renderStatusGrid(node, entries) {
  node.innerHTML = '';
  entries.forEach(([label, value]) => {
    const wrapper = document.createElement('div');
    wrapper.className = 'status-card';
    wrapper.innerHTML = `<dt>${label}</dt><dd>${value}</dd>`;
    node.appendChild(wrapper);
  });
}

function renderModelStatus(modelStatus) {
  renderStatusGrid(el.modelStatus, Object.entries(modelStatus));
}

function renderMeetingStatus(meeting) {
  const fallback = [['transcription', 'idle'], ['summary', 'idle'], ['qa', 'idle'], ['tts', 'idle']];
  const source = meeting ? Object.entries(meeting.status || {}) : fallback;
  renderStatusGrid(el.meetingStatus, source);
}

function renderSources(sources) {
  el.sourcesList.innerHTML = '';
  if (!sources || sources.length === 0) {
    el.sourcesList.innerHTML = '<div class="source-item"><strong>No grounding sources yet</strong><span>When retrieval hits, the supporting transcript and summary excerpts show up here.</span></div>';
    return;
  }

  sources.forEach((source) => {
    const card = document.createElement('div');
    card.className = 'source-item';
    card.innerHTML = `<strong>${source.source_id} · ${source.title}</strong><span>${source.excerpt}</span>`;
    el.sourcesList.appendChild(card);
  });
}

function renderAnswer(answer, audioUrl = null, meta = '') {
  el.answerText.textContent = answer || 'No answer yet.';
  el.answerMeta.textContent = meta || 'Grounding and provider details will appear here.';
  if (audioUrl) {
    el.answerAudio.src = audioUrl;
    el.answerAudio.classList.remove('hidden');
  } else {
    el.answerAudio.pause();
    el.answerAudio.src = '';
    el.answerAudio.classList.add('hidden');
    stopAudioReactiveBars();
  }
}

function renderArtifactLinks(artifactUrls) {
  el.artifactLinks.innerHTML = '';
  const labels = {
    meeting_audio: 'Meeting audio',
    raw_transcript: 'Raw transcript file',
    transcript: 'Clean transcript file',
    summary: 'Summary file',
    latest_voice_reply: 'Latest voice reply',
  };
  Object.entries(labels).forEach(([key, label]) => {
    const url = artifactUrls?.[key];
    const row = document.createElement('div');
    row.className = 'artifact-link-row';
    row.innerHTML = url
      ? `<span>${label}</span><a href="${url}" target="_blank" rel="noopener noreferrer">Open</a>`
      : `<span>${label}</span><span class="artifact-muted">Not created yet</span>`;
    el.artifactLinks.appendChild(row);
  });
}

function renderArtifactLog(entries) {
  el.artifactLog.innerHTML = '';
  if (!entries || entries.length === 0) {
    el.artifactLog.innerHTML = '<div class="log-entry"><strong>No artifact events yet</strong><span>The pipeline log will appear here as files and outputs are created.</span></div>';
    return;
  }

  [...entries].reverse().forEach((entry) => {
    const row = document.createElement('div');
    row.className = 'log-entry';
    row.innerHTML = `
      <div class="log-entry-head">
        <strong>${entry.stage}</strong>
        <span>${new Date(entry.time).toLocaleString()}</span>
      </div>
      <div class="log-entry-body">${entry.message}</div>
    `;
    el.artifactLog.appendChild(row);
  });
}

function renderConversationThread(chatHistory) {
  el.conversationThread.innerHTML = '';
  if (!chatHistory || chatHistory.length === 0) {
    el.conversationThread.innerHTML = '<div class="conversation-empty"><strong>No conversation yet</strong><span>Start with a typed question or hold to talk. Follow-ups stay in context automatically.</span></div>';
    return;
  }

  chatHistory.forEach((entry) => {
    const fragment = el.conversationItemTemplate.content.cloneNode(true);
    fragment.querySelector('.conversation-question').textContent = entry.question || 'Untitled question';
    fragment.querySelector('.conversation-answer').textContent = entry.answer || 'No answer recorded.';
    const meta = [entry.answer_provider, entry.answer_note, entry.created_at ? new Date(entry.created_at).toLocaleString() : null]
      .filter(Boolean)
      .join(' · ');
    fragment.querySelector('.conversation-meta').textContent = meta || 'No metadata';
    el.conversationThread.appendChild(fragment);
  });

  el.conversationThread.scrollTop = el.conversationThread.scrollHeight;
}

function renderMeetingList() {
  el.meetingList.innerHTML = '';
  el.meetingCount.textContent = String(state.meetings.length);
  state.meetings.forEach((meeting) => {
    const fragment = el.meetingItemTemplate.content.cloneNode(true);
    const button = fragment.querySelector('.meeting-item');
    fragment.querySelector('.meeting-title').textContent = meeting.title;
    fragment.querySelector('.meeting-preview').textContent = meeting.transcript_preview || 'No transcript yet.';
    fragment.querySelector('.meeting-meta').textContent = `${new Date(meeting.updated_at).toLocaleString()} · ${meeting.answer_count} turns`;
    if (meeting.id === state.currentMeetingId) {
      button.classList.add('active');
    }
    button.addEventListener('click', () => loadMeetingDetail(meeting.id));
    el.meetingList.appendChild(fragment);
  });
}

function updateVoiceButtonLabel() {
  if (state.voiceRecorder && state.voiceRecorder.state !== 'inactive') {
    el.voiceQuestionButton.textContent = isHandsFreeEnabled() ? 'Listening… auto-stop' : 'Release to send';
    return;
  }
  el.voiceQuestionButton.textContent = isHandsFreeEnabled() ? 'Tap to speak hands-free' : 'Hold to talk';
}

function updateActionAvailability(meeting) {
  const hasMeeting = Boolean(meeting);
  const hasContent = Boolean((meeting?.transcript || '').trim() || (meeting?.summary || '').trim() || (meeting?.live_transcript_preview || '').trim());
  el.recordToggle.disabled = !hasMeeting;
  el.summarizeButton.disabled = !hasMeeting || !(meeting?.transcript || '').trim();
  el.askButton.disabled = !hasMeeting || !hasContent;
  el.voiceQuestionButton.disabled = !hasMeeting || !hasContent;
  updateVoiceButtonLabel();
}

function renderOverviewCards(meeting) {
  el.overviewLivePreview.textContent = meeting?.live_transcript_preview || 'No live transcription yet.';
  el.overviewSummary.textContent = meeting?.summary || 'No summary yet.';
  const lastChat = meeting?.chat_history?.[meeting.chat_history.length - 1];
  el.overviewAnswer.textContent = lastChat?.answer || 'No answers yet.';
}

function renderMeetingDetail(meeting) {
  state.currentMeetingId = meeting.id;
  const summaryRecord = state.meetings.find((entry) => entry.id === meeting.id);
  if (summaryRecord) {
    summaryRecord.transcript_preview = (meeting.transcript || meeting.live_transcript_preview || '').slice(0, 120);
    summaryRecord.updated_at = meeting.updated_at;
    summaryRecord.answer_count = (meeting.chat_history || []).length;
  }

  renderMeetingList();
  renderMeetingStatus(meeting);
  updateActionAvailability(meeting);
  renderOverviewCards(meeting);
  renderConversationThread(meeting.chat_history || []);
  renderArtifactLinks(meeting.artifact_urls || {});
  renderArtifactLog(meeting.artifact_log || []);

  el.workspaceTitle.textContent = meeting.title;
  el.workspaceSubtitle.textContent = `Workspace: ${meeting.workspace} · Updated ${new Date(meeting.updated_at).toLocaleString()}`;
  el.livePreviewBox.value = meeting.live_transcript_preview || '';
  el.transcriptBox.value = meeting.transcript || '';
  el.rawTranscriptBox.value = meeting.raw_transcript || '';
  el.summaryBox.value = meeting.summary || '';

  const lastChat = [...(meeting.chat_history || [])].reverse()[0];
  if (lastChat) {
    const answerMeta = [lastChat.answer_provider, lastChat.answer_note].filter(Boolean).join(' — ');
    renderAnswer(lastChat.answer, lastChat.audio_url || meeting.artifact_urls?.latest_voice_reply, answerMeta);
    renderSources(lastChat.sources || []);
  } else {
    renderAnswer('No answer yet.');
    renderSources([]);
  }
}

async function refreshMeetings() {
  const previousMeetingId = state.currentMeetingId;
  state.meetings = await api('/api/meetings');
  renderMeetingList();
  if (previousMeetingId) {
    const existing = state.meetings.find((entry) => entry.id === previousMeetingId);
    if (existing) {
      await loadMeetingDetail(previousMeetingId, false);
      return;
    }
  }
  if (state.meetings[0]) {
    await loadMeetingDetail(state.meetings[0].id, false);
    return;
  }
  disconnectMeetingStream();
  updateActionAvailability(null);
  renderMeetingStatus(null);
  renderOverviewCards(null);
}

async function loadMeetingDetail(meetingId, refreshList = true) {
  const meeting = await api(`/api/meetings/${meetingId}`);
  if (refreshList) {
    const existingIndex = state.meetings.findIndex((entry) => entry.id === meetingId);
    if (existingIndex >= 0) {
      state.meetings[existingIndex] = {
        ...state.meetings[existingIndex],
        updated_at: meeting.updated_at,
        transcript_preview: (meeting.transcript || meeting.live_transcript_preview || '').slice(0, 120),
        answer_count: (meeting.chat_history || []).length,
      };
    }
  }
  connectMeetingStream(meetingId);
  renderMeetingDetail(meeting);
}

async function createMeeting() {
  const title = window.prompt('Meeting title', `Meeting ${new Date().toLocaleTimeString()}`);
  const meeting = await api('/api/meetings/start', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title }),
  });
  await refreshMeetings();
  renderMeetingDetail(meeting);
  switchTab('capture');
  setFeedback(el.captureFeedback, 'Meeting created. Start recording when ready.', 'success');
  setFeedback(el.qaFeedback, 'Conversation tab is ready after the meeting has content.', 'success');
}

async function ensureRecorder() {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error('Browser microphone APIs are unavailable here.');
  }
  return navigator.mediaDevices.getUserMedia({ audio: true, video: false });
}

function queuePreviewUpload(meetingId, blob) {
  const sequence = ++state.previewSequence;
  state.previewUploadChain = state.previewUploadChain.then(async () => {
    if (state.isStoppingMeeting) return;
    const response = await api(`/api/meetings/${meetingId}/transcribe-preview?mode=meeting`, {
      method: 'POST',
      headers: {
        'content-type': blob.type || 'audio/webm',
        'x-filename': `meeting-preview-${sequence}.webm`,
      },
      body: blob,
    });
    state.previewRenderedSequence = Math.max(state.previewRenderedSequence, sequence);
    setFeedback(el.captureFeedback, `Streaming preview pushed via ${response.provider}.`, 'success');
  }).catch((error) => {
    setFeedback(el.captureFeedback, error.message, 'error');
  });
}

async function uploadFinalMeetingAudio(meetingId, blob) {
  try {
    const response = await api(`/api/meetings/${meetingId}/transcribe?mode=meeting`, {
      method: 'POST',
      headers: {
        'content-type': blob.type || 'audio/webm',
        'x-filename': 'meeting-recording.webm',
      },
      body: blob,
    });
    renderMeetingDetail(response.meeting);
    await refreshMeetings();
    switchTab('transcript');
    setFeedback(el.captureFeedback, `Transcript finalized via ${response.provider}. Summary regenerated automatically.`, 'success');
  } catch (error) {
    setFeedback(el.captureFeedback, error.message, 'error');
  } finally {
    state.recordingMode = 'idle';
    state.isStoppingMeeting = false;
    clearRecordingTimer();
    el.recordToggle.textContent = 'Start meeting recording';
    el.recordingState.textContent = 'Ready';
  }
}

async function toggleMeetingRecording() {
  const meeting = currentMeeting();
  if (!meeting) return;

  if (state.recordingMode === 'meeting') {
    state.recordingMode = 'finalizing';
    state.isStoppingMeeting = true;
    el.recordToggle.textContent = 'Finalizing…';
    el.recordingState.textContent = 'Finalizing';
    setFeedback(el.captureFeedback, 'Stopping recording and finalizing transcript…');
    state.mediaRecorder.stop();
    return;
  }

  try {
    stopAnswerPlaybackForBargeIn();
    const stream = await ensureRecorder();
    state.liveChunks = [];
    state.previewUploadChain = Promise.resolve();
    state.previewSequence = 0;
    state.previewRenderedSequence = 0;
    state.isStoppingMeeting = false;
    state.mediaRecorder = new MediaRecorder(stream);
    state.mediaRecorder.ondataavailable = (event) => {
      if (!event.data || event.data.size === 0) return;
      state.liveChunks.push(event.data);
      if (!state.isStoppingMeeting) {
        const snapshotBlob = new Blob(state.liveChunks, { type: state.mediaRecorder.mimeType || 'audio/webm' });
        queuePreviewUpload(meeting.id, snapshotBlob);
      }
    };
    state.mediaRecorder.onstop = async () => {
      const fullBlob = new Blob(state.liveChunks, { type: state.mediaRecorder.mimeType || 'audio/webm' });
      stream.getTracks().forEach((track) => track.stop());
      await state.previewUploadChain;
      await uploadFinalMeetingAudio(meeting.id, fullBlob);
    };
    state.mediaRecorder.start(PREVIEW_INTERVAL_MS);
    state.recordingMode = 'meeting';
    el.recordToggle.textContent = 'Stop and finalize';
    el.recordingState.textContent = 'Recording';
    startRecordingTimer();
    switchTab('capture');
    setFeedback(el.captureFeedback, 'Recording… live transcript preview will update while you speak.', 'success');
  } catch (error) {
    setFeedback(el.captureFeedback, error.message, 'error');
  }
}

async function summarizeMeeting() {
  const meeting = currentMeeting();
  if (!meeting) return;
  setFeedback(el.captureFeedback, 'Regenerating summary…');
  try {
    const detail = await api(`/api/meetings/${meeting.id}/summarize`, { method: 'POST' });
    renderMeetingDetail(detail);
    await refreshMeetings();
    switchTab('summary');
    setFeedback(el.captureFeedback, 'Summary regenerated.', 'success');
  } catch (error) {
    setFeedback(el.captureFeedback, error.message, 'error');
  }
}

async function askQuestion() {
  const meeting = currentMeeting();
  if (!meeting) return;
  stopAnswerPlaybackForBargeIn();
  const question = el.questionInput.value.trim();
  if (!question) {
    setFeedback(el.qaFeedback, 'Enter a question first.', 'error');
    return;
  }
  setFeedback(el.qaFeedback, 'Thinking…');
  try {
    const response = await api(`/api/meetings/${meeting.id}/ask`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ question, speak_reply: el.speakToggle.checked }),
    });
    renderMeetingDetail(response.meeting);
    renderSources(response.sources);
    renderAnswer(response.answer, response.audio_url, `${response.answer_provider} — ${response.answer_note}`);
    el.questionInput.value = '';
    await refreshMeetings();
    switchTab('talk');
    setFeedback(el.qaFeedback, `Answered via ${response.answer_provider}. ${response.answer_note}`, 'success');
  } catch (error) {
    setFeedback(el.qaFeedback, error.message, 'error');
  }
}

function cleanupVoiceMonitor() {
  const monitor = state.voiceMonitor;
  if (monitor.rafId) {
    cancelAnimationFrame(monitor.rafId);
    monitor.rafId = null;
  }
  if (monitor.source) {
    monitor.source.disconnect();
    monitor.source = null;
  }
  if (monitor.analyser) {
    monitor.analyser.disconnect();
    monitor.analyser = null;
  }
  if (monitor.context) {
    monitor.context.close().catch(() => {});
    monitor.context = null;
  }
  monitor.dataArray = null;
  monitor.silenceStartedAt = null;
  monitor.detectedSpeech = false;
  monitor.stream = null;
}

async function enableHandsFreeMonitor(stream) {
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return;
  const context = new AudioContextClass();
  const source = context.createMediaStreamSource(stream);
  const analyser = context.createAnalyser();
  analyser.fftSize = 1024;
  source.connect(analyser);

  const monitor = state.voiceMonitor;
  monitor.context = context;
  monitor.source = source;
  monitor.analyser = analyser;
  monitor.dataArray = new Uint8Array(analyser.frequencyBinCount);
  monitor.silenceStartedAt = null;
  monitor.detectedSpeech = false;
  monitor.stream = stream;
  await context.resume();

  const tick = () => {
    if (!state.voiceRecorder || state.voiceRecorder.state === 'inactive') {
      cleanupVoiceMonitor();
      return;
    }
    analyser.getByteTimeDomainData(monitor.dataArray);
    let peak = 0;
    for (let i = 0; i < monitor.dataArray.length; i += 1) {
      peak = Math.max(peak, Math.abs(monitor.dataArray[i] - 128));
    }
    const normalized = peak / 128;
    const now = Date.now();
    if (normalized > 0.075) {
      monitor.detectedSpeech = true;
      monitor.silenceStartedAt = null;
    } else if (monitor.detectedSpeech) {
      if (!monitor.silenceStartedAt) {
        monitor.silenceStartedAt = now;
      }
      const elapsed = now - (state.voiceTurnStartedAt || now);
      if (elapsed > 1200 && now - monitor.silenceStartedAt > 1100) {
        endVoiceQuestion();
        return;
      }
    }
    monitor.rafId = requestAnimationFrame(tick);
  };

  tick();
}

async function beginVoiceQuestion(event) {
  if (event) event.preventDefault();
  if (isHandsFreeEnabled() && event && ['mousedown', 'mouseup', 'mouseleave', 'touchstart', 'touchend', 'touchcancel'].includes(event.type)) {
    return;
  }
  const meeting = currentMeeting();
  if (!meeting || (state.voiceRecorder && state.voiceRecorder.state !== 'inactive')) return;
  try {
    stopAnswerPlaybackForBargeIn();
    const stream = await ensureRecorder();
    state.voiceChunks = [];
    state.voiceTurnStartedAt = Date.now();
    state.voiceRecorder = new MediaRecorder(stream);
    state.voiceRecorder.ondataavailable = (evt) => {
      if (evt.data.size > 0) state.voiceChunks.push(evt.data);
    };
    state.voiceRecorder.onstop = async () => {
      const blob = new Blob(state.voiceChunks, { type: state.voiceRecorder.mimeType || 'audio/webm' });
      stream.getTracks().forEach((track) => track.stop());
      cleanupVoiceMonitor();
      updateVoiceButtonLabel();
      await uploadVoiceQuestion(meeting.id, blob);
    };
    state.voiceRecorder.start();
    updateVoiceButtonLabel();
    if (isHandsFreeEnabled()) {
      await enableHandsFreeMonitor(stream);
      setFeedback(el.qaFeedback, 'Listening hands-free… pause naturally and I will send the turn.', 'success');
    } else {
      setFeedback(el.qaFeedback, 'Listening… release when your turn is done.', 'success');
    }
  } catch (error) {
    cleanupVoiceMonitor();
    setFeedback(el.qaFeedback, error.message, 'error');
  }
}

function endVoiceQuestion(event) {
  if (event) event.preventDefault();
  if (isHandsFreeEnabled() && event && ['mouseup', 'mouseleave', 'touchend', 'touchcancel'].includes(event.type)) {
    return;
  }
  if (state.voiceRecorder && state.voiceRecorder.state !== 'inactive') {
    state.voiceRecorder.stop();
    updateVoiceButtonLabel();
    setFeedback(el.qaFeedback, 'Uploading voice turn and generating reply…');
  }
}

async function uploadVoiceQuestion(meetingId, blob) {
  try {
    const response = await api(`/api/meetings/${meetingId}/voice-question?speak_reply=${el.speakToggle.checked ? 'true' : 'false'}`, {
      method: 'POST',
      headers: {
        'content-type': blob.type || 'audio/webm',
        'x-filename': 'voice-question.webm',
      },
      body: blob,
    });
    renderMeetingDetail(response.meeting);
    renderSources(response.sources);
    renderAnswer(response.answer, response.audio_url, `${response.answer_provider} — ${response.answer_note}`);
    await refreshMeetings();
    switchTab('talk');
    setFeedback(el.qaFeedback, `Voice turn answered via ${response.answer_provider}. ${response.answer_note}`, 'success');
  } catch (error) {
    setFeedback(el.qaFeedback, error.message, 'error');
  }
}

function createReactiveBars() {
  el.audioReactiveBars.innerHTML = '';
  for (let i = 0; i < AUDIO_BAR_COUNT; i += 1) {
    const bar = document.createElement('span');
    bar.className = 'audio-bar';
    el.audioReactiveBars.appendChild(bar);
  }
}

async function ensureAudioVisualizer() {
  if (state.audioVisualizer.analyser) return;
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return;
  const context = new AudioContextClass();
  const source = context.createMediaElementSource(el.answerAudio);
  const analyser = context.createAnalyser();
  analyser.fftSize = 64;
  source.connect(analyser);
  analyser.connect(context.destination);
  state.audioVisualizer.context = context;
  state.audioVisualizer.source = source;
  state.audioVisualizer.analyser = analyser;
  state.audioVisualizer.dataArray = new Uint8Array(analyser.frequencyBinCount);
}

function stopAudioReactiveBars() {
  if (state.audioVisualizer.rafId) {
    cancelAnimationFrame(state.audioVisualizer.rafId);
    state.audioVisualizer.rafId = null;
  }
  Array.from(el.audioReactiveBars.children).forEach((bar, index) => {
    bar.style.height = `${14 + (index % 3) * 4}px`;
  });
}

async function startAudioReactiveBars() {
  await ensureAudioVisualizer();
  const { context, analyser, dataArray } = state.audioVisualizer;
  if (!context || !analyser || !dataArray) return;
  await context.resume();

  const bars = Array.from(el.audioReactiveBars.children);
  const tick = () => {
    analyser.getByteFrequencyData(dataArray);
    bars.forEach((bar, index) => {
      const value = dataArray[index % dataArray.length] || 0;
      const height = 12 + Math.round((value / 255) * 58);
      bar.style.height = `${height}px`;
    });
    state.audioVisualizer.rafId = requestAnimationFrame(tick);
  };

  stopAudioReactiveBars();
  tick();
}

function attachAudioVisualizerEvents() {
  createReactiveBars();
  stopAudioReactiveBars();
  el.answerAudio.addEventListener('play', () => {
    startAudioReactiveBars();
  });
  el.answerAudio.addEventListener('pause', stopAudioReactiveBars);
  el.answerAudio.addEventListener('ended', stopAudioReactiveBars);
}

function handleVoiceButtonClick(event) {
  if (!isHandsFreeEnabled()) return;
  event.preventDefault();
  if (state.voiceRecorder && state.voiceRecorder.state !== 'inactive') {
    endVoiceQuestion(event);
  } else {
    beginVoiceQuestion(event);
  }
}

async function init() {
  renderSecureContext();
  attachAudioVisualizerEvents();
  updateVoiceButtonLabel();
  const status = await api('/api/model-status');
  renderModelStatus(status);
  await refreshMeetings();
  switchTab('overview');
}

el.newMeetingButton.addEventListener('click', createMeeting);
el.recordToggle.addEventListener('click', toggleMeetingRecording);
el.summarizeButton.addEventListener('click', summarizeMeeting);
el.askButton.addEventListener('click', askQuestion);
el.handsfreeToggle.addEventListener('change', () => {
  updateVoiceButtonLabel();
  const message = isHandsFreeEnabled()
    ? 'Hands-free mode on. Tap once and I will auto-stop after you pause.'
    : 'Hold-to-talk mode on.';
  setFeedback(el.qaFeedback, message, 'success');
});
el.tabButtons.forEach((button) => {
  button.addEventListener('click', () => switchTab(button.dataset.tab));
});
el.voiceQuestionButton.addEventListener('click', handleVoiceButtonClick);
el.voiceQuestionButton.addEventListener('mousedown', beginVoiceQuestion);
el.voiceQuestionButton.addEventListener('touchstart', beginVoiceQuestion, { passive: false });
el.voiceQuestionButton.addEventListener('mouseup', endVoiceQuestion);
el.voiceQuestionButton.addEventListener('mouseleave', endVoiceQuestion);
el.voiceQuestionButton.addEventListener('touchend', endVoiceQuestion);
el.voiceQuestionButton.addEventListener('touchcancel', endVoiceQuestion);

document.addEventListener('DOMContentLoaded', init);
