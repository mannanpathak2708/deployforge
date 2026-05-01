package com.deployforge.taskmanager.service;

import com.deployforge.taskmanager.model.Task;
import com.deployforge.taskmanager.model.TaskStatus;
import com.deployforge.taskmanager.repository.TaskRepository;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
public class TaskService {

    private final TaskRepository repository;

    public TaskService(TaskRepository repository) {
        this.repository = repository;
    }

    public List<Task> findAll() {
        return repository.findAll();
    }

    public Optional<Task> findById(Long id) {
        return repository.findById(id);
    }

    public List<Task> findByStatus(TaskStatus status) {
        return repository.findByStatus(status);
    }

    public Task create(Task task) {
        return repository.save(task);
    }

    public Optional<Task> update(Long id, Task updated) {
        return repository.findById(id).map(existing -> {
            existing.setTitle(updated.getTitle());
            existing.setDescription(updated.getDescription());
            existing.setStatus(updated.getStatus());
            existing.setPriority(updated.getPriority());
            existing.setAssignedTo(updated.getAssignedTo());
            return repository.save(existing);
        });
    }

    public boolean delete(Long id) {
        if (!repository.existsById(id)) {
            return false;
        }
        repository.deleteById(id);
        return true;
    }
}
