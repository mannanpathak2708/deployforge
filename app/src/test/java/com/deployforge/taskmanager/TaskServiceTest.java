package com.deployforge.taskmanager;

import com.deployforge.taskmanager.model.Priority;
import com.deployforge.taskmanager.model.Task;
import com.deployforge.taskmanager.model.TaskStatus;
import com.deployforge.taskmanager.repository.TaskRepository;
import com.deployforge.taskmanager.service.TaskService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TaskServiceTest {

    @Mock
    private TaskRepository repository;

    @InjectMocks
    private TaskService service;

    private Task sample;

    @BeforeEach
    void setUp() {
        sample = new Task();
        sample.setId(1L);
        sample.setTitle("Provision EC2 cluster");
        sample.setStatus(TaskStatus.TODO);
        sample.setPriority(Priority.HIGH);
    }

    @Test
    void findAll_returnsAllTasks() {
        when(repository.findAll()).thenReturn(List.of(sample));
        assertThat(service.findAll()).hasSize(1);
        verify(repository).findAll();
    }

    @Test
    void findById_returnsTaskWhenExists() {
        when(repository.findById(1L)).thenReturn(Optional.of(sample));
        assertThat(service.findById(1L)).isPresent();
    }

    @Test
    void findById_returnsEmptyWhenMissing() {
        when(repository.findById(99L)).thenReturn(Optional.empty());
        assertThat(service.findById(99L)).isEmpty();
    }

    @Test
    void create_persistsTask() {
        when(repository.save(any(Task.class))).thenReturn(sample);
        Task created = service.create(sample);
        assertThat(created.getTitle()).isEqualTo("Provision EC2 cluster");
        verify(repository).save(sample);
    }

    @Test
    void update_modifiesExistingTask() {
        Task modifications = new Task();
        modifications.setTitle("Provision EC2 cluster - updated");
        modifications.setStatus(TaskStatus.IN_PROGRESS);
        modifications.setPriority(Priority.HIGH);

        when(repository.findById(1L)).thenReturn(Optional.of(sample));
        when(repository.save(any(Task.class))).thenAnswer(inv -> inv.getArgument(0));

        Optional<Task> result = service.update(1L, modifications);

        assertThat(result).isPresent();
        assertThat(result.get().getStatus()).isEqualTo(TaskStatus.IN_PROGRESS);
        assertThat(result.get().getTitle()).contains("updated");
    }

    @Test
    void delete_returnsTrueWhenTaskExists() {
        when(repository.existsById(1L)).thenReturn(true);
        assertThat(service.delete(1L)).isTrue();
        verify(repository).deleteById(1L);
    }

    @Test
    void delete_returnsFalseWhenMissing() {
        when(repository.existsById(99L)).thenReturn(false);
        assertThat(service.delete(99L)).isFalse();
        verify(repository, never()).deleteById(any());
    }
}
