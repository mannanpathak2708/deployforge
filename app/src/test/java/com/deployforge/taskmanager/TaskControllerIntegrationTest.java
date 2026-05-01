package com.deployforge.taskmanager;

import com.deployforge.taskmanager.model.Priority;
import com.deployforge.taskmanager.model.Task;
import com.deployforge.taskmanager.model.TaskStatus;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class TaskControllerIntegrationTest {

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;

    @Test
    void getAllTasks_returns200() throws Exception {
        mockMvc.perform(get("/api/tasks"))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON));
    }

    @Test
    void healthEndpoint_returnsOk() throws Exception {
        mockMvc.perform(get("/api/tasks/health"))
                .andExpect(status().isOk())
                .andExpect(content().string("OK"));
    }

    @Test
    void actuatorHealth_returnsUp() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void prometheusEndpoint_isExposed() throws Exception {
        mockMvc.perform(get("/actuator/prometheus"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("jvm_memory_used_bytes")));
    }

    @Test
    void createAndRetrieveTask_fullRoundTrip() throws Exception {
        Task task = new Task();
        task.setTitle("Configure kubeadm on master node");
        task.setDescription("Initialise control plane with pod CIDR 10.244.0.0/16");
        task.setStatus(TaskStatus.IN_PROGRESS);
        task.setPriority(Priority.HIGH);
        task.setAssignedTo("mannan");

        String json = objectMapper.writeValueAsString(task);

        String location = mockMvc.perform(post("/api/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").exists())
                .andExpect(jsonPath("$.title").value("Configure kubeadm on master node"))
                .andExpect(jsonPath("$.status").value("IN_PROGRESS"))
                .andReturn().getResponse().getHeader("Location");

        mockMvc.perform(get(location))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.assignedTo").value("mannan"));
    }

    @Test
    void createTask_withBlankTitle_returns400() throws Exception {
        Task task = new Task();
        task.setTitle("");
        mockMvc.perform(post("/api/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(task)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void getNonExistentTask_returns404() throws Exception {
        mockMvc.perform(get("/api/tasks/99999"))
                .andExpect(status().isNotFound());
    }

    @Test
    void deleteNonExistentTask_returns404() throws Exception {
        mockMvc.perform(delete("/api/tasks/99999"))
                .andExpect(status().isNotFound());
    }
}
