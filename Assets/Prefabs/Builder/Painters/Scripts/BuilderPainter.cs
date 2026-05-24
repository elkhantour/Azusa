using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;

namespace Island
{
    namespace Builder
    {

        public enum PainterMode
        {
            Island,
            NomadTown,
            Temple,
        }

        public class BuilderPainter : MonoBehaviour
        {

            [SerializeField] protected CameraManager _cameraManager;

            [Header("Builder")]
            [SerializeField] protected GameObject chunkPrefab;
            [SerializeField] protected int maxChunks = 10;
            [SerializeField] protected float minRadius = 1f;
            [SerializeField] protected float maxRadius = 10f;
            [SerializeField] protected float scrollSensitivity = 1f;
            [SerializeField] protected float radiusPadding = 0f;
            [SerializeField] protected GameObject _root;

            [Header("Controls")]
            [SerializeField] private KeyCode deleteKey = KeyCode.Delete;

            protected List<GameObject> _spawnedChunks = new();
            protected List<RadialMask> _circlesMask = new();
            protected GameObject _activeChunk;
            protected bool _isPlacingNew = false;
            protected bool _isMovingExisting = false;
            protected Island _island;

            protected virtual void OnPlacementConfirmation() { }

            public virtual void Init(Island island)
            {
                _island = island;
            }

            public void Enable()
            {
                enabled = true;
                UpdateChunksVisibility();
                _cameraManager.FreezeZoom();
            }

            public void Disable()
            {
                enabled = false;
                DeleteCurrentChunk();
                UpdateChunksVisibility();
                _cameraManager.UnfreezeZoom();
            }

            protected float GetActiveChunkRadius()
            {
                return _activeChunk != null ? _activeChunk.transform.localScale.x / 2.0f : 0.0f;
            }

            protected Vector3 GetActiveChunkPosition()
            {
                return _activeChunk != null ? _activeChunk.transform.position : Vector3.zero;
            }

            protected void UpdateChunksVisibility()
            {
                _spawnedChunks.ForEach(ch => ch.SetActive(enabled));
            }

            void Update()
            {

                // Cancel if hovering UI
                if (EventSystem.current.IsPointerOverGameObject())
                    return;

                HandleInput();

                if (_isPlacingNew || _isMovingExisting)
                {
                    UpdateChunkPosition();
                    UpdateChunkRadius();
                    HandlePlacementConfirmation();
                }
                else
                {
                    HandleSelection();
                }
            }


            private void HandlePlacementConfirmation()
            {
                // On click, drop the chunk and return to idle state
                if (Input.GetMouseButtonDown(0))
                {
                    if (_isPlacingNew)
                    {
                        _spawnedChunks.Add(_activeChunk);
                        _circlesMask.Add(new RadialMask()
                        {
                            Position = GetActiveChunkPosition(),
                            Radius = GetActiveChunkRadius(),
                        });
                    }

                    // Auto-generate whenever a chunk is placed or repositioned
                    if (_spawnedChunks.Count > 0)
                    {
                        OnPlacementConfirmation();
                    }

                    _isPlacingNew = false;
                    _isMovingExisting = false;
                    _activeChunk.GetComponent<ChunkHelper>().SetActive(false);
                    _activeChunk = null;

                }
            }

            private void HandleInput()
            {
                // Spawn new chunk
                if (!_isPlacingNew && !_isMovingExisting)
                {
                    if (_spawnedChunks.Count < maxChunks)
                    {
                        SpawnNewChunk();
                    }
                    else
                    {
                        Debug.LogWarning("Max chunk limit reached!");
                    }
                }

                // Delete selected chunk
                if (Input.GetKeyDown(deleteKey) && _isMovingExisting &&
                    _activeChunk != null)
                {
                    DeleteCurrentChunk();
                }

            }
	    
            private void SpawnNewChunk()
            {
                _activeChunk = Instantiate(chunkPrefab, _root?.transform);
                _isPlacingNew = true;
                _activeChunk.GetComponent<ChunkHelper>().SetActive(true);
            }

            private void UpdateChunkPosition()
            {
                Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
                // Create a mathematical plane at y=0
                Plane groundPlane = new Plane(Vector3.up, Vector3.zero);

                if (groundPlane.Raycast(ray, out float enter))
                {
                    Vector3 hitPoint = ray.GetPoint(enter);
                    _activeChunk.transform.position =
                        new Vector3(hitPoint.x, 0, hitPoint.z);
                }
            }

            private void UpdateChunkRadius()
            {
                float scroll = Input.mouseScrollDelta.y;
                if (Mathf.Abs(scroll) > 0.01f)
                {
                    // Assuming the "radius" is represented by the localScale of the helper
                    Vector3 scale = _activeChunk.transform.localScale;
                    float newRadius = Mathf.Clamp(scale.x + (scroll * scrollSensitivity),
                                                  minRadius, maxRadius);
                    _activeChunk.transform.localScale =
                        new Vector3(newRadius, scale.y, newRadius);
                }
            }



            private void HandleSelection()
            {
                if (Input.GetMouseButtonDown(0))
                {

                    Debug.Log("Cast");

                    Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
                    if (Physics.Raycast(ray, out RaycastHit hit))
                    {

                        Debug.Log("HIT!");


                        // Check if we hit one of our chunks
                        if (_spawnedChunks.Contains(hit.collider.gameObject))
                        {
                            Debug.Log("FOUND!");

                            _activeChunk = hit.collider.gameObject;
                            _activeChunk.GetComponent<ChunkHelper>().SetActive(true);
                            _isMovingExisting = true;
                        }
                    }
                }
            }

            private void DeleteCurrentChunk()
            {
                _spawnedChunks.Remove(_activeChunk);
                // TODO handle circle mask removal
                Destroy(_activeChunk);
                _activeChunk = null;
                _isMovingExisting = false;
                _isPlacingNew = false;
            }


        }



    }
}
